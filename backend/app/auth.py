from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import firebase_admin
from firebase_admin import auth, credentials

# Initialize Firebase Admin once
# Download your serviceAccountKey.json from Firebase Console:
# Project Settings → Service Accounts → Generate New Private Key
# Place it at D:\FlutterProjects\receipt_iq\backend\serviceAccountKey.json

try:
    firebase_admin.get_app()
except ValueError:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)

security = HTTPBearer()

def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)) -> str:
    try:
        decoded = auth.verify_id_token(credentials.credentials)
        return decoded["uid"]
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
