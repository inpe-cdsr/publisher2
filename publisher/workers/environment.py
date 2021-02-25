from os import getenv

from publisher.environment import str2bool


# RabbitMQ environment variables
RT_USER = getenv('RT_USER', 'guest')
RT_PASSWORD = getenv('RT_PASSWORD', 'guest')
RT_HOST = getenv('RT_HOST', 'inpe_cdsr_rabbitmq')
RT_PORT = getenv('RT_PORT', '5672')

# Celery environment variables and configuration
CELERY_ALWAYS_EAGER = str2bool(getenv('CELERY_ALWAYS_EAGER', 'False'))
CELERY_BROKER_URL = f'amqp://{RT_USER}:{RT_PASSWORD}@{RT_HOST}:{RT_PORT}//'
CELERY_RESULT_BACKEND = getenv('CELERY_RESULT_BACKEND', 'rpc://')
