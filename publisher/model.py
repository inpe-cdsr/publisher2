# -*- coding: utf-8 -*-

from abc import ABC, abstractmethod
from json import dumps
from sqlite3 import connect as sqlite3_connect

from pandas import read_sql
from sqlalchemy import create_engine
from sqlalchemy.exc import SQLAlchemyError

from publisher.environment import PR_FILES_PATH, PR_LOGGING_LEVEL
from publisher.logger import create_logger


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


class DBConnection(ABC):
    @abstractmethod
    def execute(self, query, params=None, is_transaction=False):
        raise NotImplementedError

    def select_from_collections(self):
        return self.execute('SELECT * FROM bdc.collections;')


class PostgreSQLConnection(DBConnection):

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


class SQLiteConnection(DBConnection):
    # http://pythonclub.com.br/gerenciando-banco-dados-sqlite3-python-parte1.html

    def __init__(self, db_uri):
        self.__db_uri = db_uri
        # init a new test database before running the test cases
        self.__init_db()

    def __init_db(self):
        # open schema file
        with open(f'{PR_FILES_PATH}/cdsr_catalog_test_schema.sql', 'r') as data:
            schema = data.read()

        # execute the schema file
        self.execute(schema, is_transaction=True)

    def execute(self, query, params=None, is_transaction=False):
        # logger.debug('SQLiteConnection.execute()')
        # logger.debug(f'SQLiteConnection.execute() - is_transaction: {is_transaction}')
        # logger.debug(f'SQLiteConnection.execute() - query: {query}')
        # logger.debug(f'SQLiteConnection.execute() - params: {params}')

        try:
            # INSERT, UPDATE and DELETE
            if is_transaction:
                db = sqlite3_connect(self.__db_uri)
                cursor = db.cursor()

                # execute many clauses together
                cursor.executescript(query)

                db.commit()
                db.close()
                return

            # SELECT (return dataframe)
            # return read_sql(query, con=self.engine)

        except SQLAlchemyError as error:
            logger.error(f'SQLiteConnection.execute() - An error occurred during query execution.')
            logger.error(f'SQLiteConnection.execute() - error.code: {error.code} - error.args: {error.args}')
            logger.error(f'SQLiteConnection.execute() - error: {error}\n')

            raise SQLAlchemyError(error)
