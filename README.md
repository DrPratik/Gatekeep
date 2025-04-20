# 🚗 Automatic Number Plate Recognition (ANPR) System

This project is part of my M.Tech Dissertation. It implements an Automatic Number Plate Recognition (ANPR) system using deep learning and OCR to detect and verify vehicle license plates from uploaded images.

## 🔍 Objective

To design and deploy a web-based ANPR system that:
- Detects vehicle license plates from images.
- Extracts text using OCR.
- Verifies vehicles against a MongoDB database (residents vs. visitors).
- Supports RESTful API endpoints.

## 🛠️ Technologies Used

- Python
- OpenCV
- PyTesseract
- YOLO
- MongoDB Atlas
- Docker & GitHub Actions
- Connexion + Flask for REST API

## 🌐 Deployment

The app is containerized with Docker and deployed to a remote VM using GitHub Actions CI/CD.

### GitHub Actions Workflow Includes:
- Building multi-platform Docker images.
- Pushing to Docker Hub.
- SSH-based deployment to the target server.

## 📦 API Endpoints

| Endpoint              | Method | Description                          |
|-----------------------|--------|--------------------------------------|
| `/detect_file`        | POST   | Upload image and detect license plate |
| `/verify_file`        | POST   | Detect + verify vehicle from image   |
| `/annotate_file`      | POST   | Annotate and return the image        |

## 📸 Sample Flow

1. User uploads an image of a vehicle.
2. The license plate is detected using YOLO model.
3. OCR extracts the license plate text.
4. The result is matched with MongoDB:
   - If found in residents → marked as resident.
   - Else → added/updated in visitors collection.

## 🐳 Docker
live swagger ui for this http://80.225.225.183:8080/ui/
