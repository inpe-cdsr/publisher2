from publisher.environment import PR_LOGGING_LEVEL
from publisher.logger import create_logger


# create logger object
__logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


def fill_string_with_left_zeros(string, max_string_size=3):
    # get the diff (i.e. how many `0` will be added before the string)
	diff = max_string_size - len(string)
    # add the number of `0` before the string
	return ('0' * diff) + string


def print_line(size_line=130):
    __logger.info(f'\n{ "-" * size_line }\n')
