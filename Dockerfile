FROM python:3.8.5-slim-buster

WORKDIR /app

COPY requirements.txt /app
RUN pip install -r requirements.txt

COPY . /app

CMD ["python", "main.py"]
