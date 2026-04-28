from fastapi import FastAPI
from .routers import receipts, analytics

app = FastAPI(title="ReceiptIQ API", version="1.0.0")

app.include_router(receipts.router)
app.include_router(analytics.router)


@app.get("/")
def root():
    return {"status": "ReceiptIQ backend running"}
