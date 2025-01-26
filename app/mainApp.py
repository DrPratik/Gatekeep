import os
import os.path
import sys
import signal
import connexion
import urllib.request
import urllib.error
import flask
import tempfile
from PIL import Image
from PIL import ImageFont
from PIL import ImageDraw
import pytesseract
from ultralytics import YOLO
import cv2
import numpy as np
import re
import requests
import logging
import torch
import io
from inference_sdk import InferenceHTTPClient

CLIENT = InferenceHTTPClient(
    api_url="https://detect.roboflow.com",
    api_key="Pf4e2ngl5SyxRoYiriMh"
)


logging.basicConfig(level=logging.DEBUG, format='%(asctime)s %(levelname)s %(message)s')

# Setup handler to catch SIGTERM from Docker
def sigterm_handler(_signo, _stack_frame):
    print('Sigterm caught - closing down')
    sys.exit()

def detect(filename, threshold):
    detections = CLIENT.infer(filename, model_id="license-plate-recognition-rxg4e/4")

    # Process detections
    results = []
    for prediction in detections.get('predictions', []):
        x = prediction.get('x')
        y = prediction.get('y')
        width = prediction.get('width')
        height = prediction.get('height')
        confidence = prediction.get('confidence')
        class_name = prediction.get('class')
        class_id = prediction.get('class_id')
        detection_id = prediction.get('detection_id')

        results.append((class_id, confidence, (x, y, width, height)))

    logging.debug(f"Processed detections: {results}")
    return results

def get_image_type(filename):
    img = Image.open(filename)
    image_type = img.format.lower()
    img.close()
    if not (image_type == 'jpeg' or image_type == 'png'): raise Exception("Image has to be JPEG or PNG")
    return image_type

def annotate(filename, threshold):
    detections = detect(filename, threshold)
    img = Image.open(filename)
    drw = ImageDraw.Draw(img)
    font = ImageFont.truetype(r'DejaVuSans.ttf', 16)
    for detection in detections:
        label = detection[0]
        confidence = detection[1]
        bounds = detection[2]

        box_width = int(float(bounds[2]))
        box_height = int(float(bounds[3]))
        box_center_x = int(float(bounds[0]))
        box_center_y = int(float(bounds[1]))
        x_min = int(box_center_x - box_width/2)
        x_max = int(box_center_x + box_width/2)
        y_min = int(box_center_y - box_height/2)
        y_max = int(box_center_y + box_height/2)

        boxColor = (int(255 * (1 - (confidence ** 2))), int(255 * (confidence ** 2)), 0)
        drw.rectangle([x_min, y_min, x_max, y_max], fill=None, outline=boxColor, width=3)
        txt_width, txt_height = drw.textsize(label, font=font)
        drw.rectangle([x_min, y_min-(txt_height+4), x_min+txt_width+4, y_min], fill=boxColor, outline=boxColor, width=3)
        drw.text((x_min+2, y_min-(txt_height+2)), label, (255, 255, 255), font=font)
    img.save(filename)

def ocr(filename,detections):
    predictions = detections.get('predictions', [])
    plate_num = ""

    for prediction in predictions:
        x = prediction.get('x')
        y = prediction.get('y')
        width = prediction.get('width')
        height = prediction.get('height')
        confidence = prediction.get('confidence')
        class_name = prediction.get('class')
        class_id = prediction.get('class_id')
        detection_id = prediction.get('detection_id')

        # Calculate bounding box coordinates
        x_min = int(x - width / 2)
        x_max = int(x + width / 2)
        y_min = int(y - height / 2)
        y_max = int(y + height / 2)

        # Read and process the image
        img = cv2.imread(filename, 0)
        gray = img[y_min:y_max, x_min:x_max]
        gray = cv2.resize(gray, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)

        ret, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_OTSU | cv2.THRESH_BINARY_INV)
        rect_kern = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        dilation = cv2.dilate(thresh, rect_kern, iterations=1)

        try:
            contours, hierarchy = cv2.findContours(dilation, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
        except:
            ret_img, contours, hierarchy = cv2.findContours(dilation, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

        sorted_contours = sorted(contours, key=lambda ctr: cv2.boundingRect(ctr)[0])
        im2 = gray.copy()
        arr = []

        for cnt in sorted_contours:
            x, y, w, h = cv2.boundingRect(cnt)
            height, width = im2.shape

            if height / float(h) > 3: continue
            ratio = h / float(w)
            if ratio < 1: continue
            area = h * w
            if width / float(w) > 33: continue
            if area < 100: continue

            rect = cv2.rectangle(im2, (x, y), (x + w, y + h), (0, 255, 0), 2)
            roi = thresh[y - 5:y + h + 5, x - 5:x + w + 5]
            roi = cv2.bitwise_not(roi)
            roi = cv2.medianBlur(roi, 5)
            arr.append(roi)

        for x in range(len(arr)):
            if (len(arr) - x) <= 4 or x == 2 or x == 3:
                text = pytesseract.image_to_string(arr[x], config='-c tessedit_char_whitelist=0123456789 --psm 8 --oem 3')
            else:
                text = pytesseract.image_to_string(arr[x], config='-c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ --psm 8 --oem 3')
            clean_text = re.sub('[\W_]+', '', text)
            plate_num += clean_text

    pattern = '^[A-Z]{2}[ -][0-9]{1,2}(?: [A-Z])?(?: [A-Z]*)? [0-9]{4}$'
    cv2.destroyAllWindows()
    return plate_num

    

def detect_from_url(url, threshold):
    try:
        # Use mkstemp to generate unique temporary filename
        fd, filename = tempfile.mkstemp()
        os.close(fd)
        urllib.request.urlretrieve(url, filename)
        image_type = get_image_type(filename)
        os.rename(filename, filename + '.' + image_type)
        filename = filename + '.' + image_type
        res = detect(filename, threshold)
        os.unlink(filename)
        return res
    except urllib.error.HTTPError as err:
        return 'HTTP error', err.code
    except:
        return 'An error occurred', 500

def detect_from_file():
    try:
        file_to_upload = connexion.request.files['image_file']
        threshold = connexion.request.form.get('threshold', 0.9)  # Set default threshold to 0.9 if not provided
        threshold = float(threshold)  # Ensure threshold is a float
        print(f"Received threshold: {threshold}, type: {type(threshold)}")  # Debugging statement
        # Use mkstemp to generate unique temporary filename
        fd, filename = tempfile.mkstemp()
        os.close(fd)
        file_to_upload.save(filename)
        logging.debug(f"Image saved to {filename}")
        image_type = get_image_type(filename)
        logging.debug(f"Image type: {image_type}")
        os.rename(filename, filename + '.' + image_type)
        filename = filename + '.' + image_type
        logging.debug(f"Image renamed to {filename}")
        res = detect(filename, threshold)
        logging.debug(f"Detections: {res}")
        text = ""
        if len(res):
            text = ocr(filename, res)
            logging.debug(f"Number plate text: {text}")
        os.unlink(filename)
        return {
            "detections": res,
            "number_plate": text
        }
    except urllib.error.HTTPError as err:
        return 'HTTP error', err.code
    except Exception as e:
        logging.error(f"An error occurred: {e}")
        return 'An error occurred', 500
    
def verify_from_file():
    try:
        file_to_upload = connexion.request.files['image_file']
        threshold = float(connexion.request.form['threshold'])
        # Use mkstemp to generate unique temporary filename
        fd, filename = tempfile.mkstemp()
        os.close(fd)
        file_to_upload.save(filename)
        image_type = get_image_type(filename)
        os.rename(filename, filename + '.' + image_type)
        filename = filename + '.' + image_type
        res = detect(filename, threshold)
        text = ""
        if len(res):
            text = ocr(filename, res)
            req = requests.post("https://nameless-savannah-82632.herokuapp.com/visitor/checkvisitors",json={"numberplate": text})
            data = req.json()

        os.unlink(filename)
        return {
            "detections" : res,
            "number_plate" : text,
            "verification" : data
        }
    except urllib.error.HTTPError as err:
        return 'HTTP error', err.code
    except:
        return 'An error occurred', 500

def annotate_from_file():
    try:
        file_to_upload = connexion.request.files['image_file']
        threshold = float(connexion.request.form['threshold'])
        fd, filename = tempfile.mkstemp(".image")
        os.close(fd)
        file_to_upload.save(filename)
        image_type = get_image_type(filename)
        os.rename(filename, filename + '.' + image_type)
        filename = filename + '.' + image_type
        annotate(filename, threshold)
        res = flask.send_file(filename)
        os.unlink(filename)
        return res
    except urllib.error.HTTPError as err:
        return 'HTTP error', err.code
    except:
        return 'An error occurred', 500

def annotate_from_url(url, threshold):
    try:
        fd, filename = tempfile.mkstemp()
        os.close(fd)
        urllib.request.urlretrieve(url, filename)
        image_type = get_image_type(filename)
        os.rename(filename, filename + '.' + image_type)
        filename = filename + '.' + image_type
        annotate(filename, threshold)
        res = flask.send_file(filename)
        os.unlink(filename)
        return res
    except urllib.error.HTTPError as err:
        return 'HTTP error', err.code
    except:
        return 'An error occurred', 500

# Create API:
app = connexion.App(__name__)
# For compatibility we will make the API available both with and without a version basepath
app.add_api('swag.yaml')
app.add_api('swag.yaml', base_path='/1.0')

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, sigterm_handler)
    app.run(port=8080, server='gevent')
