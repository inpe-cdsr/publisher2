from os import walk


class Publisher:
    def __init__(self, BASE_DIR):
        self.BASE_DIR = BASE_DIR

    def main(self):
        """
        # traverse root directory, and list directories as dirs and files as files
        for root, dirs, files in os.walk(BASE_DIR):

            path = root.split(os.sep)
            print((len(path) - 1) * '---', os.path.basename(root))

            for file in files:
                print(len(path) * '---', file)

        """

        for dirpath, dirs, files in walk(self.BASE_DIR):
            #print('d: ', dirpath)
            for file in files:
                print('f: ', dirpath + '/' + file)
