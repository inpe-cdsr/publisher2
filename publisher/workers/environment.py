from os import getenv


# RabbitMQ environment variables
RT_USER = getenv('RT_USER', 'guest')
RT_PASSWORD = getenv('RT_PASSWORD', 'guest')
RT_HOST = getenv('RT_HOST', 'inpe_cdsr_rabbitmq')
RT_PORT = getenv('RT_PORT', '5672')

# Celery environment variables and configuration
# celery broker
CELERY_BROKER_URL = f'amqp://{RT_USER}:{RT_PASSWORD}@{RT_HOST}:{RT_PORT}//'
# celery backend
CELERY_RESULT_BACKEND = getenv('CELERY_RESULT_BACKEND', 'redis://:redis@inpe_cdsr_redis:6379/0')
# number of chunks that are executed in one task
CELERY_CHUNKS_PER_TASKS = int(getenv('CELERY_CHUNKS_PER_TASKS', 100))
