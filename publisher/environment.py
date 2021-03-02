from os import getenv

from publisher.logger import AVAILABLE_LEVELS, INFO


def str2bool(value):
    '''Convert string to boolean.'''
    # Source: https://stackoverflow.com/a/715468
    return str(value).lower() in ('true', 't', '1', 'yes', 'y')


##################################################
# Flask environment variables
##################################################

FLASK_SECRET_KEY = getenv('FLASK_SECRET_KEY', 'test')
FLASK_TESTING = str2bool(getenv('FLASK_TESTING', 'False'))


##################################################
# Publisher environment variables
##################################################

# base directory to recursively traverse, base directory to search assets
PR_BASE_DIR = getenv('PR_BASE_DIR', '/TIFF')
PR_LOGGING_LEVEL = getenv('PR_LOGGING_LEVEL', 'INFO')

# if the inserted logging level already exists, then select it,
if PR_LOGGING_LEVEL in AVAILABLE_LEVELS:
    PR_LOGGING_LEVEL = AVAILABLE_LEVELS[PR_LOGGING_LEVEL]
else:
    # else, insert a default logging level
    PR_LOGGING_LEVEL = INFO
