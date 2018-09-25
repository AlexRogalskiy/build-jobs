#!/bin/sh

MAX_ATTEMPTS=2

# cleaning the previous logs
sudo rm -rf /tmp/failed-tests /tmp/*log /tmp/*patch.tar.gz >/dev/null 2>&1

# create and activate virtual env
virtualenv --system-site-packages env
. env/bin/activate

# create SSH key pair of 4096 bits to use it for instances at Rackspace
ssh-keygen -f "${WORKSPACE}"/key -t rsa -b 4096

# Install dependencies
pip install -I pyrax ansible

#create the server machines
ansible-playbook /opt/qa/distributed-tests/create-vm.yml -e COUNT=${MACHINES_COUNT} -e  NAME=${JOB_NAME}-${BUILD_ID} -e PATH=${WORKSPACE}

for retry in $(seq 1 $MAX_ATTEMPTS)
do
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i hosts /opt/qa/distributed-tests/setup.yml -u root --skip-tags 'copy_logs' -e PATH=${WORKSPACE}
  ret=$?
  if [ $ret -eq 0 ]; then
    break
  fi
  echo 'Attempting to run again...'
done

# run the script of distributed-test
/opt/qa/distributed-tests/run-distributed-test.py --n "${MACHINES_COUNT}"
ret=$?

#copy the logs from machines before deleting
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i hosts /opt/qa/distributed-tests/setup.yml -u root --tags 'copy_logs' --private-key key

#delete the server machines
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i hosts /opt/qa/distributed-tests/delete-vm.yml
if [ $ret -ne 0 ]; then
  # Create tar file from all the failed test log files generated in /tmp
  tar -czf "$WORKSPACE"/failed-tests-logs.tgz /tmp/*.log /tmp/failed-tests
  scp -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "$LOG_KEY" failed-tests-logs.tgz "_logs-collector@http.int.rht.gluster.org:/var/www/glusterfs-logs/$JOB_NAME-logs-$BUILD_ID.tgz" || true;
  echo "Failed tests logs stored in https://ci-logs.gluster.org/$JOB_NAME-logs-$BUILD_ID.tgz"
  exit $ret
else
  exit 0
fi
