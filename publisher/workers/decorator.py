
from datetime import timedelta
from functools import wraps
from time import time

from celery.utils.log import get_task_logger


logger = get_task_logger(__name__)


def log_task(function):
    '''Decorator to celery tasks that log information.'''

    @wraps(function)
    def wrapper(self, *args, **kwargs):
        # logger.warning(f'{function.__name__} - task is executing... '
        #                f'[name: `{self.request.task}`, id: `{self.request.id}`]')
        # logger.warning(f'{function.__name__} - task args: {self.request.args}')
        # logger.warning(f'{function.__name__} - task parent_id: {self.request.parent_id}')
        # logger.warning(f'{function.__name__} - task root_id: {self.request.root_id}')

        start_time = time()
        result = function(self, *args, **kwargs)
        elapsed_time = timedelta(seconds=(time() - start_time))

        logger.warning(f'{function.__name__} - task has been executed! '
                       f'[name: `{self.request.task}`, id: `{self.request.id}`, '
                       f'elapsed time: {elapsed_time}]')

        return result

    return wrapper
