from logging import Formatter, getLogger, StreamHandler, \
                    DEBUG, INFO, WARNING

AVAILABLE_LEVELS = {
    'DEBUG': DEBUG,
    'INFO': INFO,
    'WARNING': WARNING
}

def create_logger(name, level=INFO):
    '''Create a logger object.'''

    # create logger
    logger = getLogger(name)
    logger.setLevel(level)

    # create console handler and set level to debug
    ch = StreamHandler()
    ch.setLevel(level)

    # add formatter to ch
    ch.setFormatter(
        # create formatter
        Formatter('%(asctime)s - %(name)s - %(levelname)-8s | %(message)s')
    )

    # add ch to logger
    logger.addHandler(ch)

    return logger
