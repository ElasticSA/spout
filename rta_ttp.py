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
    
    try:
        opts, args = getopt.getopt(argv,"hds:t:",["stack=","ttp="])
    except getopt.GetoptError:
        print_help()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_help()
            exit()
        elif opt in '-d':
            dry_run = True
        elif opt in ('-s', '--stack'):
            stack_version = arg
        elif opt in ('-t', '--ttp'):
            ttp_list = arg.split(',')

    el_dr_zip = f"detection-rules-{stack_version}.zip"
    el_dr_url = f"https://github.com/elastic/detection-rules/archive/v{stack_version}.zip"

    if not os.path.isfile(f"{mydir}/{el_dr_zip}"):
        print(f"Downloading: {el_dr_url}")
        download_url(el_dr_url, f"{mydir}/{el_dr_zip}")
    
    if not os.path.isdir(f"{mydir}/detection-rules-{stack_version}"):
        print(f"Extracting zip: {mydir}/{el_dr_zip}")
        with zipfile.ZipFile(f"{mydir}/{el_dr_zip}", 'r') as this_zip:
                this_zip.extractall(mydir)

    sys.path.insert(1, f"{mydir}/detection-rules-{stack_version}")
    rta = importlib.import_module('rta')

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
            print(f"RAT TTP FAILED: ", Ex)           
        print(f"RTA TTP Finished: {ttp_name}")
    
    return 0

def print_help():
    print('test.py -s <stack_version> -t <ttp,name,list>')
    print(f"--stack={default_stack_version} (stack_version)\n--ttp=ALL (ttp list)")

def download_url(url, save_path, chunk_size=4096):
    r = requests.get(url, stream=True)
    with open(save_path, 'wb') as fd:
        for chunk in r.iter_content(chunk_size=chunk_size):
            fd.write(chunk)

if __name__ == "__main__":
   main(sys.argv[1:])
