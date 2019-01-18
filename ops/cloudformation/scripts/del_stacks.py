import boto3
import json
import argparse

def is_service(stack, service):
    tags= stack['Tags']

    rez = False

    for tag in tags:
        key, value = tag['Key'], tag['Value']
        if key == 'service' and value == service:
            rez = True
            break
    return rez

def is_environment(stack, environment):
    tags= stack['Tags']

    rez = False

    for tag in tags:
        key, value = tag['Key'], tag['Value']
        if key == 'Environment' and value == environment:
            rez = True
            break
    return rez

def is_status_ok(stack):
    return stack['StackStatus'] == 'CREATE_COMPLETE' or \
            stack['StackStatus'] == 'UPDATE_COMPLETE' or \
            stack['StackStatus'] == 'DELETE_FAILED'

def get_version(stack):
    rez = None
    for tag in stack['Tags']:
        key, value = tag['Key'], tag['Value']
        if key == 'Version':
            rez = value
    return rez

def main(environment, service, curr_version):
    cf = boto3.client('cloudformation', region_name='us-east-1')

    responce = cf.describe_stacks()

    for stack in responce['Stacks']:
        if not is_status_ok(stack):
            continue
        if not is_environment(stack, environment):
            continue
        if not is_service(stack, service):
            continue
        # print("Stack:", stack['StackName'], stack['Tags'])
        if get_version(stack) is None or get_version(stack) != curr_version:
            print("Delete:", stack['StackName'], stack['Tags'])
            cf.delete_stack(StackName=stack['StackName'])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='List stacks')
    parser.add_argument('environment', type=str, help='Environment')
    parser.add_argument('service', type=str, help='Service')
    parser.add_argument('curr_version', type=str, help='Version')

    args = parser.parse_args()

    main(args.environment, args.service, args.curr_version)
