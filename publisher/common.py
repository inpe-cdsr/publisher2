from publisher.environment import PR_LOGGING_LEVEL
from publisher.logger import create_logger


# create logger object
__logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


def print_line(size_line=130):
    __logger.info(f'\n{ "-" * size_line }\n')
