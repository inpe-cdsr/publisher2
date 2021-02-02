# -*- coding: utf-8 -*-

from abc import ABC, abstractmethod
from json import dumps
from os import getenv
from sqlite3 import connect as sqlite3_connect

from pandas import read_sql
from psycopg2 import connect as psycopg2_connect
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
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
        self._create_engine()

    def _create_engine(self):
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


class PostgreSQLTestConnection(PostgreSQLConnection):

    def __init__(self):
        self.PGUSER = getenv('PGUSER', 'postgres')
        self.PGPASSWORD = getenv('PGPASSWORD', 'postgres')
        self.PGHOST = getenv('PGHOST', 'inpe_cdsr_postgis')
        self.PGPORT = int(getenv('PGPORT', 5432))
        self.PGDATABASE = getenv('PGDATABASE', 'cdsr_catalog_test')

        self.__init_db()

        super().__init__()

    def __recreate_test_database(self):
        # connect to `postgres` database in order to recreate other database
        con = psycopg2_connect(
            user=self.PGUSER, password=self.PGPASSWORD,
            host=self.PGHOST, port=self.PGPORT,
            dbname='postgres'
        )

        con.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

        cur = con.cursor()

        cur.execute(f'DROP DATABASE IF EXISTS {self.PGDATABASE};')
        cur.execute(f'CREATE DATABASE {self.PGDATABASE};')

        con.close()

        logger.info(f'\nRecreated `{self.PGDATABASE}` database.')

    def __restore_test_database(self):
        # connect with test database
        con = psycopg2_connect(
            user=self.PGUSER, password=self.PGPASSWORD,
            host=self.PGHOST, port=self.PGPORT,
            dbname=self.PGDATABASE
        )

        cur = con.cursor()

        # open schema file
        with open(f'tests/db/cdsr_catalog_test.sql', 'r') as data:
            schema = data.read()

        cur.execute(schema)

        con.commit()
        con.close()

        logger.info(f'Restored `{self.PGDATABASE}` database.\n')

    def __init_db(self):
        self.__recreate_test_database()
        self.__restore_test_database()

    def delete_from_items(self):
        self.execute('DELETE FROM bdc.items;', is_transaction=True)
