from email.mime import message
import os
import firebase_admin
from firebase_admin import credentials, messaging

_cred_path = os.path.join(os.path.dirname(__file__), "..", "..", "firebase-credentials.json")

if not firebase_admin._apps:
    cred = credentials.Certificate(_cred_path)
    firebase_admin.initialize_app(cred)


def send_match_notification(fcm_token: str, blood_type: str, hospital_name: str, distance_km: float):
    if not fcm_token:
        return  # donor has no registered device token yet

    message = messaging.Message(
        notification=messaging.Notification(
            title=f"{blood_type} needed nearby",
            body=f"{hospital_name} — about {distance_km:.1f} km away. Can you help?",
        ),
        token=fcm_token,
    )
    try:
        print(f"DEBUG: Attempting push to FCM Token: {fcm_token[:20]}...")
        response = messaging.send(message)
        print(f"DEBUG: FCM Message sent successfully: {response}")
    except Exception as e:
        # Don't let a single bad/expired token crash the whole request flow
        print(f"Failed to send notification: {e}")

def send_response_notification(fcm_token: str, donor_name: str, hospital_name: str, status: str):
    if not fcm_token:
        return

    if status == "accepted":
        title = "A donor can help!"
        body = f"{donor_name} responded to your request at {hospital_name}."
    else:
        return  # don't notify on decline — not actionable/useful to the requester

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        token=fcm_token,
    )
    try:
        messaging.send(message)
    except Exception as e:
        print(f"Failed to send response notification: {e}")