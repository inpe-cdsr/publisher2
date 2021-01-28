from os import getenv

from publisher.logger import AVAILABLE_LEVELS, INFO
from publisher.util import str2bool


FLASK_SECRET_KEY = getenv('FLASK_SECRET_KEY', 'test')

# base directory to recursively traverse
PR_BASE_DIR = getenv('PR_BASE_DIR', '/')
# path to files folder
PR_FILES_PATH = getenv('PR_FILES_PATH', 'files')

PR_IS_TO_GET_DATA_FROM_DB = str2bool(getenv('PR_IS_TO_GET_DATA_FROM_DB', 'True'))

PR_LOGGING_LEVEL = getenv('PR_LOGGING_LEVEL', 'INFO')

# if the inserted logging level already exists, then select it,
# else, insert a default logging level
if PR_LOGGING_LEVEL in AVAILABLE_LEVELS:
    PR_LOGGING_LEVEL = AVAILABLE_LEVELS[PR_LOGGING_LEVEL]
else:
    PR_LOGGING_LEVEL = INFO
