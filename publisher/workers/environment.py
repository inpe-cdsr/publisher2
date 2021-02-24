from os import getenv


# RabbitMQ environment variables
RT_USER = getenv('RT_USER', 'guest')
RT_PASSWORD = getenv('RT_PASSWORD', 'guest')
RT_HOST = getenv('RT_HOST', 'inpe_cdsr_rabbitmq')
RT_PORT = getenv('RT_PORT', '5672')

# Celery configuration
CY_BROKER_URL = f'amqp://{RT_USER}:{RT_PASSWORD}@{RT_HOST}:{RT_PORT}//'
CY_RESULT_BACKEND = getenv('CY_RESULT_BACKEND', 'rpc://')
