from datetime import datetime
from itertools import islice
from time import sleep

from celery import Celery
from celery.result import allow_join_result
from celery.states import FAILURE, SUCCESS
from celery.utils.log import get_task_logger

from publisher.common import print_line
from publisher.workers.decorator import log_task
from publisher.workers.environment import CELERY_BROKER_URL, CELERY_RESULT_BACKEND, CELERY_CHUNKS_PER_TASKS
from publisher.workers.processing_worker import process_items, CELERY_PROCESSING_QUEUE
from publisher.util import PublisherWalk, SatelliteMetadata


logger = get_task_logger(__name__)


CELERY_MASTER_QUEUE='master'

# initialize Celery
celery = Celery(
    'publisher.workers.master_worker',  # celery name
    broker=CELERY_BROKER_URL,
    backend=CELERY_RESULT_BACKEND
)

# get configuration from file
celery.config_from_object('publisher.workers.celery_config')


@celery.task(bind=True, queue=CELERY_MASTER_QUEUE,
             name='publisher.workers.master_worker.master')
@log_task
def master(self, base_dir: str, query: dict, df_collections: dict) -> None:
    '''Master task. It calls the workers.'''

    print_line()

    logger.info(f'master - base_dir: {base_dir}')
    logger.info(f'master - query: {query}\n')

    # convert dates from str to date
    query['start_date'] = datetime.strptime(query['start_date'].split('T')[0], '%Y-%m-%d')
    query['end_date'] = datetime.strptime(query['end_date'].split('T')[0], '%Y-%m-%d')

    # p_walk is a generator that returns just valid directories
    p_walk = PublisherWalk(base_dir, query, SatelliteMetadata())

    logger.info('master - `p_walk` has been created.')

    # statistics
    tasks_count = 0  # number of executed tasks
    chunks_per_tasks_count = 0  # number of chunks per tasks

    # list of executed tasks
    tasks = []

    # run the tasks by chunks.
    while True:
        logger.info('master - getting a slice of `p_walk`...')

        # exhaust the generator to get a list of values, because generator is not serializable
        p_walk_top = list(islice(p_walk, CELERY_CHUNKS_PER_TASKS)) # get the first N elements

        # if the p_walk generator has been exhausted, then stop the loop
        if not p_walk_top:
            break

        # get the number of records to process
        p_walk_top_size = len(p_walk_top)
        logger.info(f'master - sending `{p_walk_top_size}` chunks to `process_items` task...')

        # run `process_items` task
        tasks.append(
            process_items.apply_async((p_walk_top, df_collections), queue=CELERY_PROCESSING_QUEUE)
        )

        # get statistics
        chunks_per_tasks_count += p_walk_top_size
        tasks_count += 1

        logger.info(f'master - `{chunks_per_tasks_count}` chunks per tasks have been sent to '
                    '`process_items` task.')
        logger.info(f'master - `{tasks_count}` `process_items` tasks have been executed.\n')

    # save the errors
    p_walk.save_the_errors_in_the_database()

    logger.warning(f'master - total of executed tasks: {tasks_count}')

    with allow_join_result():
        while True:
            # get all tasks that are running yet
            running_tasks = list(filter(lambda t: not t.ready(), tasks))
            logger.warning(f'master - total of running tasks: {len(running_tasks)}')

            # if there are tasks running, then sleep some seconds and try again
            if running_tasks:
                sleep(3)
                continue
            # else, if all tasks have been executed, then get all failure tasks
            # and save them in the database

            # get all success tasks
            success_tasks = list(filter(lambda t: t.state == SUCCESS, tasks))
            logger.warning(f'master - total of success tasks: {len(success_tasks)}')

            # get all failure tasks
            failure_tasks = list(filter(lambda t: t.state == FAILURE, tasks))
            logger.warning(f'master - total of failure tasks: {len(failure_tasks)}')

            for task in success_tasks:
                p_walk = task.args[0]

                logger.info(f'master - task: {task}')
                logger.info(f'master - task.id: {task.id}')

                logger.info(f'master - p_walk first: {p_walk[0]}')
                logger.info(f'master - p_walk last: {p_walk[-1]}')

                logger.info(f'master - task.state: {task.state}\n')

                # forget result
                task.forget()

            logger.info(f'master - all failure tasks have been saved in the database.')
            break

    logger.info('master - `master` task has been executed.\n')
