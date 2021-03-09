from cerberus import Validator
from datetime import datetime

# L1 is ignored
GEO_PROCESSING_ALLOWED_LIST = ['2', '2B', '3', '4']
RADIO_PROCESSING_ALLOWED_LIST = ['DN', 'SR']


# function to convert from string to datetime
to_date = lambda s: datetime.strptime(s, '%Y-%m-%d')

# function to transform the string on upper case
to_upper_case = lambda s: s.upper()

# function to convert string to a sorted list
to_list = lambda s: sorted(to_upper_case(str(s)).split(','))


class PublisherValidator(Validator):
    def _validate_it_cannot_be_greater_than(self, target_field, self_field, self_value):
        '''Check if the field is greater than the other one.
        First field cannot be greater than the other one.

        The rule's arguments are validated against this schema:
        {'type': 'string'}
        '''

        if target_field not in self.document:
            self._error(self_field, f'`{target_field}` field is not in the document.')

        target_value = self.document[target_field]
        if self_value > target_value:
            self._error(self_field, f'`{self_field}` field cannot be greater than `{target_field}` field.')


QUERY_SCHEMA = {
    'satellite': {
        'type': 'string', 'coerce': to_upper_case, 'regex': 'AMAZONIA1|^CBERS[1-4][A-B]*|^LANDSAT\d',
        'required': True
    },
    'sensor': {
        'type': 'string', 'coerce': to_upper_case,
        'default': None, 'nullable': True
    },
    'start_date': {
        'type': 'datetime', 'coerce': to_date, 'it_cannot_be_greater_than': 'end_date',
        'required': True
    },
    'end_date': {
        'type': 'datetime', 'coerce': to_date,
        'required': True
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
        'type': 'list', 'coerce': to_list, 'allowed': GEO_PROCESSING_ALLOWED_LIST,
        'default': ','.join(GEO_PROCESSING_ALLOWED_LIST)
    },
    'radio_processing': {
        'type': 'list', 'coerce': to_list, 'allowed': RADIO_PROCESSING_ALLOWED_LIST,
        'default': ','.join(RADIO_PROCESSING_ALLOWED_LIST)
    }
}


def validate(data: dict, schema: dict) -> (bool, dict, dict):
    v = PublisherValidator(schema)
    return v.validate(data), v.document, v.errors
