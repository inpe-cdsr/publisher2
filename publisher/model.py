# -*- coding: utf-8 -*-

from abc import ABC, abstractmethod
from json import dumps, loads
from os import getenv
from sqlite3 import connect as sqlite3_connect

from pandas import read_sql
from psycopg2 import connect as psycopg2_connect
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from sqlalchemy import create_engine
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.pool import NullPool

from publisher.environment import FLASK_TESTING, PR_FILES_PATH, PR_LOGGING_LEVEL
from publisher.logger import create_logger


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


class DBConnection(ABC):
    @abstractmethod
    def execute(self, query: str, params: dict=None, is_transaction: bool=False):
        raise NotImplementedError

    def select_from_collections(self):
        return self.execute('SELECT * FROM bdc.collections ORDER BY name;')


class PostgreSQLConnection(DBConnection):

    def __init__(self):
        self.PGUSER = getenv('PGUSER', 'postgres')
        self.PGPASSWORD = getenv('PGPASSWORD', 'postgres')
        self.PGHOST = getenv('PGHOST', 'inpe_cdsr_postgis')
        self.PGPORT = int(getenv('PGPORT', 5432))
        self.PGDATABASE = getenv('PGDATABASE', 'cdsr_catalog')

        self._create_engine()

    def _create_engine(self):
        # the elements for connection are got by environment variables
        # engine_connection = 'postgresql+psycopg2://'
        engine_connection = (f'postgresql+psycopg2://{self.PGUSER}:{self.PGPASSWORD}'
                             f'@{self.PGHOST}:{self.PGPORT}/{self.PGDATABASE}')

        try:
            # `NullPool prevents the Engine from using any connection more than once`
            self.engine = create_engine(engine_connection, poolclass=NullPool)

        except SQLAlchemyError as error:
            logger.error(f'PostgreSQLConnection.__init__() - An error occurred during engine creation.')
            logger.error(f'PostgreSQLConnection.__init__() - error.code: {error.code} - error.args: {error.args}')
            logger.error(f'PostgreSQLConnection.__init__() - error: {error}\n')

            raise SQLAlchemyError(error)

    def execute(self, query: str, params: dict=None, is_transaction: bool=False):
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
    # abstract class

    def __init__(self):
        # initialize the environment variables
        super().__init__()
        self.init_file = None

    def __recreate_test_database(self):
        # connect to `postgres` database in order to recreate other database
        con = psycopg2_connect(
            user=self.PGUSER, password=self.PGPASSWORD,
            host=self.PGHOST, port=self.PGPORT,
            dbname='postgres'
        )

        con.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

        cur = con.cursor()

        # recreate the main database
        cur.execute(f'DROP DATABASE IF EXISTS {self.PGDATABASE};')
        cur.execute(f'CREATE DATABASE {self.PGDATABASE};')

        con.close()

        logger.info(f'Recreated `{self.PGDATABASE}` database.')

    def __restore_test_database(self):
        # connect with database
        con = psycopg2_connect(
            user=self.PGUSER, password=self.PGPASSWORD,
            host=self.PGHOST, port=self.PGPORT,
            dbname=self.PGDATABASE
        )

        cur = con.cursor()

        # open schema file
        with open(self.init_file, 'r') as data:
            schema = data.read()

        cur.execute(schema)

        con.commit()
        con.close()

        logger.info(f'Restored `{self.PGDATABASE}` database.\n')

    def init_db(self):
        self.__recreate_test_database()
        self.__restore_test_database()


class PostgreSQLCatalogTestConnection(PostgreSQLTestConnection):
    # concrete class

    def __init__(self):
        super().__init__()
        self.PGDATABASE = 'cdsr_catalog_test'
        self._create_engine()
        self.init_file = 'tests/db/cdsr_catalog_test.sql'

    def delete_from_items(self):
        self.execute('DELETE FROM bdc.items;', is_transaction=True)

    def select_from_items(self, to_csv: str=None):
        result = self.execute('SELECT name, collection_id, start_date::timestamp, '
                              'end_date::timestamp, assets, metadata, geom, min_convex_hull '
                              'FROM bdc.items ORDER BY name;')

        result['assets'] = result['assets'].astype('str')
        result['metadata'] = result['metadata'].astype('str')

        if to_csv is not None:
            result.to_csv(f'tests/publisher/{to_csv}', index=False)

        return result

    @staticmethod
    def create_item_insert_clause(item: dict, collection_id: int, srid: int=4326) -> str:
        '''Create `INSERT` clause to bdc.items table based on item metadata.'''

        min_x = item['bbox'][0]
        min_y = item['bbox'][1]
        max_x = item['bbox'][2]
        max_y = item['bbox'][3]

        properties = item['properties']
        datetime = properties['datetime']

        return (
            # delete old item before adding a new one, if it exists
            f'DELETE FROM bdc.items WHERE name=\'{properties["name"]}\'; '
            # insert new item
            'INSERT INTO bdc.items '
            '(name, collection_id, start_date, end_date, '
            'cloud_cover, assets, metadata, geom, min_convex_hull, srid) '
            'VALUES '
            f'(\'{properties["name"]}\', {collection_id}, \'{datetime}\', \'{datetime}\', '
            f'NULL, \'{dumps(item["assets"])}\', \'{dumps(properties)}\', '
            f'ST_GeomFromGeoJSON(\'{dumps(item["geometry"])}\'), '
            f'ST_MakeEnvelope({min_x}, {min_y}, {max_x}, {max_y}, {srid}), {srid});'
        )


class PostgreSQLPublisherConnection(PostgreSQLTestConnection):
    # concrete class

    def __init__(self):
        super().__init__()
        self.PGDATABASE = 'cdsr_publisher'
        self._create_engine()
        self.init_file = 'tests/db/cdsr_publisher.sql'

    def delete_from_task_error(self):
        self.execute('DELETE FROM task_error;', is_transaction=True)

    def select_from_task_error(self):
        df_result = self.execute(
            'SELECT message, metadata, type FROM task_error ORDER BY message, metadata;'
        )
        # convert dataframe to JSON and convert it to dict
        return loads(df_result.to_json(orient='records'))

    @staticmethod
    def create_task_error_insert_clause(error: dict) -> str:
        '''Create `INSERT` clause to task_error table based on error metadata.'''

        return (
            'INSERT INTO task_error (message, metadata, type) VALUES '
            f'(\'{error["message"]}\', \'{dumps(error["metadata"])}\', \'{error["type"]}\');'
        )


class DBFactory:

    @staticmethod
    def factory() -> DBConnection:
        # if the user is testing the application (i.e. running test cases),
        # then return the test database
        if FLASK_TESTING:
            # testing
            return PostgreSQLCatalogTestConnection()

        # else, return the normal database
        # production or development
        return PostgreSQLConnection()


def init_dbs():
    '''Initialize the databases.'''

    # initialize the databases just one time
    db = PostgreSQLCatalogTestConnection()
    db.init_db()
    db_publisher = PostgreSQLPublisherConnection()
    db_publisher.init_db()

    print('Databases have been initialized.\n')
