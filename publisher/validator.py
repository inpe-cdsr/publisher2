from cerberus import Validator
from datetime import datetime


# function to convert from string to datetime
to_date = lambda s: datetime.strptime(s, '%Y-%m-%d')

# function to transform the string on upper case
to_upper_case = lambda s: s.upper()


QUERY_SCHEMA = {
    'satellite': {
        'type': 'string', 'coerce': to_upper_case, 'regex': '^CBERS[1-4][A-B]*|^LANDSAT\d',
        'default': None, 'nullable': True
    },
    'sensor': {
        'type': 'string', 'coerce': to_upper_case,
        'default': None, 'nullable': True
    },
    'start_date': {
        'type': 'datetime', 'coerce': to_date,
        'default': None, 'nullable': True
    },
    'end_date': {
        'type': 'datetime', 'coerce': to_date,
        'default': None, 'nullable': True
    },
    'path': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 999,
        'default': None, 'nullable': True
    },
    'row': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 999,
        'default': None, 'nullable': True
    },
    'geo_processing': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 4,
        'default': None, 'nullable': True
    },
    'radio_processing': {
        'type': 'string', 'coerce': to_upper_case, 'allowed': ['DN', 'SR'],
        'default': None, 'nullable': True
    }
}


def validate(data, schema):
    v = Validator(schema)
    is_valid = v.validate(data)

    if is_valid:
        radio_processing = v.document['radio_processing']

        if radio_processing == 'DN':
            v.document['radio_processing'] = ['DN']
        elif radio_processing == 'SR':
            v.document['radio_processing'] = ['SR']
        else: # elif radio_processing is None
            v.document['radio_processing'] = ['DN', 'SR']

    return is_valid, v.document, v.errors
