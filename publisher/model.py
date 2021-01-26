# -*- coding: utf-8 -*-

from json import dumps

from pandas import read_sql
from sqlalchemy import create_engine
from sqlalchemy.exc import SQLAlchemyError

from publisher.environment import LOGGING_LEVEL
from publisher.logger import get_logger


# create logger object
logger = get_logger(__name__, level=LOGGING_LEVEL)


class PostgreSQLConnection():

    def __init__(self):
        try:
            # the elements for connection are got by environment variables
            self.engine = create_engine('postgresql+psycopg2://')

        except SQLAlchemyError as error:
            logger.error(f'PostgreSQLConnection.__init__() - An error occurred during engine creation.')
            logger.error(f'PostgreSQLConnection.__init__() - error.code: {error.code} - error.args: {error.args}')
            logger.error(f'PostgreSQLConnection.__init__() - error: {error}\n')

            raise SQLAlchemyError(error)

    def execute(self, query, params=None, is_transaction=False):
        # logger.debug('PostgreSQLConnection.execute()')
        # logger.debug(f'PostgreSQLConnection.execute() - is_transaction: {is_transaction}')
        # logger.debug(f'PostgreSQLConnection.execute() - query: {query}')
        # logger.debug(f'PostgreSQLConnection.execute() - params: {params}')

        try:
            # INSERT, UPDATE and DELETE
            if is_transaction:
                with self.engine.begin() as connection:  # runs a transaction
                    connection.execute(query, params)
                return

            # SELECT (return ResultProxy)
            # with self.engine.connect() as connection:
            #     # convert rows from ResultProxy to list and return the object
            #     return list(connection.execute(query))

            # SELECT (return dataframe)
            return read_sql(query, con=self.engine)

        except SQLAlchemyError as error:
            logger.error(f'PostgreSQLConnection.execute() - An error occurred during query execution.')
            logger.error(f'PostgreSQLConnection.execute() - error.code: {error.code} - error.args: {error.args}')
            logger.error(f'PostgreSQLConnection.execute() - error: {error}\n')

            raise SQLAlchemyError(error)

    ####################################################################################################
    # COLLECTION
    ####################################################################################################

    def select_from_collections(self):
        return self.execute('SELECT * FROM bdc.collections;')
