from os import getenv

from publisher.logger import AVAILABLE_LEVELS, INFO


def str2bool(value):
    '''Convert string to boolean'''
    # Source: https://stackoverflow.com/a/715468
    return str(value).lower() in ('true', 't', '1', 'yes', 'y')


FLASK_SECRET_KEY = getenv('FLASK_SECRET_KEY', 'test')

FLASK_TESTING = str2bool(getenv('FLASK_TESTING', 'False'))

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
