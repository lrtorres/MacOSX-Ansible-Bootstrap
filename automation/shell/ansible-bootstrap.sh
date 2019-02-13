#!/bin/bash
# vim:set textwidth=0:
#
# Install the necessary components to run ansible on mac os x, and 
# call a remote playbook on github.
#
# Send shell output to log
#exec 1> >(logger -s -t $(hostname)) 2>&1

#export ANSIBLE_STRATEGY=debug
LOGFILE=/var/log/ansible-install.log

# Since this script executes in AQUA/UI space, we determine its
# progress via 'say' output.
function announce {
    msg="$@"
    say $msg
    echo "SITE: $msg ..."
}

function install-prereqs {

	remotePkg="CommandLineTools1012.pkg"
	localPkg="CommandLineTools1012.pkg"

	if [ ! -e "/tmp/downloads/pkg/${localPkg}" ] ; then
		mkdir -p /tmp/downloads/pkg

		# We assume that the web server is configured with a location $SERVER_ROOT/mac/Packages/ansiblemac.
		announce "Downloading xcode Command Line Tools"
		curl -o /tmp/downloads/pkg/${localPkg} https://$1/mac/Packages/ansiblemac/$remotePkg
		announce "  Done." ||  announce "  FAIL."

		announce "Installing xcode Command Line Tools"
		installer -verboseR -target / -pkg /tmp/downloads/pkg/${localPkg}
	fi

	announce "Install pip"
	curl https://bootstrap.pypa.io/get-pip.py | /usr/bin/python
	announce "  Done." ||  announce "  FAIL."
}

# This function deploys pre-configured ssh deployment keys necessary to clone playbook repo on github.
function install-ssh-keys {
   
	URL="$1/linux"
	SSH_KEY=/var/root/.ssh/git-ansible
 
	install -d -o root -g wheel -m 0700 /var/root/.ssh /var/root/.git

	if [ ! -f ${SSH_KEY} ]; then
		curl -o ${SSH_KEY} https://${URL}/git-ansible
		chown root:root ${SSH_KEY}
		chmod 600 ${SSH_KEY}
	fi

	if [ ! -f /var/root/.git/config ]; then
		echo Host github.com > /var/root/.git/config
		echo IdentityFile ~/.ssh/git-ansible >> /var/root/.git/config
	fi

}

function install-ansible {

	announce "Install ansible"
	/usr/local/bin/pip install ansible==2.6.4 
	announce "  Done." || announce "  FAIL."

	announce "Copying ansible CFG"
	if [ ! -d /etc/ansible ] ; then
		mkdir /etc/ansible 
	fi &&\
        # A mac ansible.cfg should be available, even if blank or containing default info.
	curl -o /etc/ansible/ansible.cfg https://$1/mac/ansible.cfg
	announce "  Done." || announce "  FAIL."

}

################################################################################
# MAIN
################################################################################
PROG=$0

# Replace local.webserver.domain with a server housing the requested
# packages.
WEB_SERVER=local.webserver.domain

# We must be root
if [ $UID -ne 0 ]; then
    announce "This script must be run as root."
    exit 1
fi

ROOT=

#announce "Setting Host Name"
IP=$(ipconfig getifaddr en0)
HOSTNAME=$(dig -x ${IP} ptr +short | cut -d\. -f1)
scutil --set HostName ${HOSTNAME}

# Set V to version string 10.x from product version 10.x.y
PRODUCT="$(sw_vers | grep ProductVersion | cut -f2)"
V=$(echo $PRODUCT | cut -f1,2 -d\.)

# Let's set the volume so that we can hear the 'says'. 
osascript -e "set volume 2"

announce "Installing ansible pre requisites"
(
	install-prereqs "${WEB_SERVER}"
	install-ssh-keys "${WEB_SERVER}"
	install-ansible "${WEB_SERVER}"
) &&\
announce "FAIL." || "DONE."

################################################################################
# Run Ansible Pull
################################################################################

announce "Executing ansible pull"

# gnu-tar - to fix the unarchive issue, should work once gnu tar is installed by ansible.
export PATH="/usr/local/opt/gnu-tar/libexec/gnubin:$PATH"
export MANPATH="/usr/local/opt/gnu-tar/libexec/gnuman:$MANPATH"

# Replace <github account> and <playbook repo> with appropriate values.
/usr/local/bin/ansible-pull --accept-host-key -U git@github.com:<github account>/<playbook repo> \
    --inventory=inventory \
    --private-key=/var/root/.ssh/git-ansible
