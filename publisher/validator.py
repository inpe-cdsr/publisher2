from cerberus import Validator
from datetime import datetime


# function to convert from string to datetime
to_date = lambda s: datetime.strptime(s, '%Y-%m-%d')

# function to transform the string on upper case
to_upper_case = lambda s: s.upper()


QUERY_SCHEMA = {
    'satellite': {
        'type': 'string', 'coerce': to_upper_case, 'regex': '^CBERS[1-4][A-B]*|^LANDSAT\d'
    },
    'sensor': {
        'type': 'string', 'coerce': to_upper_case
    },
    'start_date': {
        'type': 'datetime', 'coerce': to_date
    },
    'end_date': {
        'type': 'datetime', 'coerce': to_date
    },
    'path': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 360
    },
    'row': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 360
    },
    'geo_processing': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 4
    },
    'radio_processing': {
        'type': 'string', 'coerce': to_upper_case, 'allowed': ['DN', 'SR']
    }
}


def validate(data, schema):
    v = Validator(schema)
    return v.validate(data), v.document, v.errors
