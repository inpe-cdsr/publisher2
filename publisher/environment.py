from os import getenv

from publisher.logger import AVAILABLE_LEVELS, INFO
from publisher.util import str2bool


FLASK_SECRET_KEY = getenv('FLASK_SECRET_KEY', 'test')

# base directory to recursively traverse
BASE_DIR = getenv('BASE_DIR', '/')
# path to files folder
FILES_PATH = getenv('FILES_PATH', 'files')

IS_TO_GET_DATA_FROM_DB = str2bool(getenv('IS_TO_GET_DATA_FROM_DB', 'True'))

LOGGING_LEVEL = getenv('LOGGING_LEVEL', 'INFO')

# if the inserted logging level already exists, then select it,
# else, insert a default logging level
if LOGGING_LEVEL in AVAILABLE_LEVELS:
    LOGGING_LEVEL = AVAILABLE_LEVELS[LOGGING_LEVEL]
else:
    LOGGING_LEVEL = INFO
