from logging import DEBUG, Formatter, getLogger, INFO, StreamHandler


def get_logger(name, level=INFO):
    """Create a logger object"""

    # create logger
    logger = getLogger(name)
    logger.setLevel(level)

    # create console handler and set level to debug
    ch = StreamHandler()
    ch.setLevel(level)

    # add formatter to ch
    ch.setFormatter(
        # create formatter
        Formatter('%(asctime)s - %(name)s - %(levelname)s | %(message)s')
    )

    # add ch to logger
    logger.addHandler(ch)

    return logger
