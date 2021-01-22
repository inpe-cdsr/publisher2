def fill_string_with_left_zeros(string, max_string_size=3):
    # get the diff (i.e. how many `0` will be added before the string)
	diff = max_string_size - len(string)
    # add the number of `0` before the string
	return ('0' * diff) + string
