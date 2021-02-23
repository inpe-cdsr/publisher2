from os import getenv

# Celery configuration
CY_BROKER_URL = getenv('CY_BROKER_URL', 'amqp://guest:guest@inpe_cdsr_rabbitmq:5672//')
CY_RESULT_BACKEND = getenv('CY_RESULT_BACKEND', 'rpc://')
