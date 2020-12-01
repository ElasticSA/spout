#
# Run RTA TTPs from Elastic's Detection Rules project
# https://github.com/elastic/detection-rules/rta
#

import sys
import os
import getopt
import importlib
import requests
import yaml
import zipfile

mydir = os.path.dirname(__file__)
default_stack_version = '7.10.0'

def main(argv):

    stack_version = default_stack_version
    ttp_list = ['ALL']
    dry_run = False
    list_modules = None
    
    try:
        opts, args = getopt.getopt(argv,"hdl:s:t:",["stack=","ttp=","list="])
    except getopt.GetoptError:
        print_help()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_help()
            return 0
        elif opt in '-d':
            dry_run = True
        elif opt in ('-s', '--stack'):
            stack_version = arg
        elif opt in ('-t', '--ttp'):
            ttp_list = arg.split(',')
        elif opt in ('-l', '--list'):
            list_modules = arg

    rta = get_rta_modules(stack_version)

    if list_modules != None:
        if list_modules == '':
            list_modules = rta.common.CURRENT_OS

        for mod in rta.get_ttp_names(list_modules):
            print(mod)
        return 0

    if ttp_list[0] == 'ALL':
        ttp_list = rta.get_ttp_names(rta.common.CURRENT_OS)
        
    print(ttp_list)
    print("\n")

    for ttp_name in ttp_list:
        print(f"RTA TTP Start: {ttp_name}")
        try:
            ttp = importlib.import_module(f".{ttp_name}", 'rta')
            if not dry_run:
                ttp.main()
        except Exception as Ex:
            print(f"RTA TTP FAILED: ", Ex)
        print(f"RTA TTP Finished: {ttp_name}")
    
    return 0

def get_rta_modules(sver):
    # Not all stack point releases have a detection rules release
    # So we'll just always get x.y.0
    _sver = sver.split('.')
    sver = f"{_sver[0]}.{_sver[1]}.0"

    el_dr_id = f"detection-rules-{sver}"
    el_dr_url = f"https://github.com/elastic/detection-rules/archive/v{sver}.zip"

    if not os.path.isfile(f"{mydir}/{el_dr_id}.zip"):
        print(f"Downloading: {el_dr_url}")
        download_url(el_dr_url, f"{mydir}/{el_dr_id}.zip")

    if not os.path.isdir(f"{mydir}/{el_dr_id}"):
        print(f"Extracting zip: {mydir}/{el_dr_id}.zip")
        with zipfile.ZipFile(f"{mydir}/{el_dr_id}.zip", 'r') as this_zip:
                this_zip.extractall(mydir)

    sys.path.insert(1, f"{mydir}/{el_dr_id}")
    return importlib.import_module('rta')

def print_help():
    print('rta_ttp.py -s <stack_version> -t <ttp,name,list> -d')
    print('rta_ttp.py -l <os_name>')
    print(f"Defaults/example:")
    print(f"--stack={default_stack_version} (stack_version)\n--ttp=ALL (ttp list)")
    print(f"-list='' (list for current os")

def download_url(url, save_path, chunk_size=4096):
    r = requests.get(url, stream=True)
    with open(save_path, 'wb') as fd:
        for chunk in r.iter_content(chunk_size=chunk_size):
            fd.write(chunk)

if __name__ == "__main__":
   main(sys.argv[1:])
