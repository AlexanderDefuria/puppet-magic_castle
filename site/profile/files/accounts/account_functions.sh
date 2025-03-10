#!/bin/bash

kexec () {
    local TMP_KRB_CACHE=$(mktemp)
    kinit -kt /etc/krb5.keytab -c ${TMP_KRB_CACHE} &> /dev/null &&
    KRB5CCNAME=${TMP_KRB_CACHE} ${@} &&
    kdestroy -c ${TMP_KRB_CACHE} &> /dev/null
    rm -f $TMP_KRB_CACHE
}

mkhome () {
    local USERNAME=$1

    if [ -z "${USERNAME}" ]; then
        echo "ERROR::${FUNCNAME}: username unspecified"
        return 1
    fi

    if id $USERNAME &> /dev/null; then
        local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
        local USER_UID=$(SSS_NSS_USE_MEMCACHE=no id -u $USERNAME)
        local METHOD="getent/id"
    else
        local USER_INFO=$(kexec ipa user-show ${USERNAME})
        local USER_HOME=$(echo "${USER_INFO}" | grep -oP 'Home directory: \K(.*)$')
        local USER_UID=$(echo "${USER_INFO}" | grep -oP 'UID: \K([0-9].*)')
        local METHOD="ipa"
    fi

    if [ -z "${USER_HOME}" ]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: home path not defined (${METHOD})"
        return 1
    fi

    if [ -z "${USER_UID}" ]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: UID not defined (${METHOD})"
        return 1
    fi

    local RSYNC_DONE=0
    for i in $(seq 1 5); do
        rsync -opg -r -u --chown=$USER_UID:$USER_UID --chmod=Dg-rwx,o-rwx,Fg-rwx,o-rwx,u+X /etc/skel.ipa/ ${USER_HOME}
        if [ $? -eq 0 ]; then
            RSYNC_DONE=1
            break
        else
            sleep 5
        fi
    done
    if [ ! $RSYNC_DONE -eq 1 ]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: cannot copy /etc/skel.ipa in ${USER_HOME}"
        return 1
    else
        echo "INFO::${FUNCNAME} ${USERNAME}: created ${USER_HOME}"
    fi
    restorecon -F -R ${USER_HOME}
}

mkscratch () {
    local USERNAME=$1
    local WITH_HOME=$2

    if [ -z "${USERNAME}" ]; then
        echo "ERROR::${FUNCNAME}: username unspecified"
        return 1
    fi

    if id $USERNAME &> /dev/null; then
        local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
        local USER_UID=$(SSS_NSS_USE_MEMCACHE=no id -u $USERNAME)
        local METHOD="getent/id"
    else
        local USER_INFO=$(kexec ipa user-show ${USERNAME})
        local USER_HOME=$(echo "${USER_INFO}" | grep -oP 'Home directory: \K(.*)$')
        local USER_UID=$(echo "${USER_INFO}" | grep -oP 'UID: \K([0-9].*)')
        local METHOD="ipa"
    fi

    if [ -z "${USER_HOME}" ]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: home path not defined (${METHOD})"
        return 1
    fi

    if [ -z "${USER_UID}" ]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: UID not defined (${METHOD})"
        return 1
    fi

    local USER_SCRATCH="/scratch/${USERNAME}"
    if [[ ! -d "${USER_SCRATCH}" ]]; then
        mkdir -p ${USER_SCRATCH}
        if [ "$WITH_HOME" == "true" ]; then
            ln -sfT ${USER_SCRATCH} "${USER_HOME}/scratch"
            chown -h ${USER_UID}:${USER_UID} "${USER_HOME}/scratch"
        fi
        chown -h ${USER_UID}:${USER_UID} ${USER_SCRATCH}
        chmod 750 ${USER_SCRATCH}
        restorecon -F -R ${USER_SCRATCH}
        echo "INFO::${FUNCNAME} ${USERNAME}: created ${USER_SCRATCH}"
    fi
    return 0
}

mkproject() {
    local GROUP=$1
    local WITH_FOLDER=$2
    local PROJECT_GROUP="/project/$GROUP"

    if [ -z "${GROUP}" ]; then
        echo "ERROR::${FUNCNAME}: group unspecified"
        return 1
    fi

    if mkdir /var/lock/mkproject.$GROUP.lock; then
        # A new group has been created
        if [ "$WITH_FOLDER" == "true" ]; then
            local GID=$(SSS_NSS_USE_MEMCACHE=no getent group $GROUP 2> /dev/null | cut -d: -f3)
            if [ $? -eq 0 ]; then
                local GID=$(kexec ipa group-show ${GROUP} | grep -oP 'GID: \K([0-9].*)')
            fi

            if [ -z "${GID}" ]; then
                echo "ERROR::${FUNCNAME} ${GROUP}: GID not defined"
                return 1
            fi

            local PROJECT_GID="/project/$GID"
            if [ ! -d ${PROJECT_GID} ]; then
                local PROJECT_GROUP="/project/$GROUP"
                mkdir -p ${PROJECT_GID}
                chown root:${GID} ${PROJECT_GID}
                chmod 2770 ${PROJECT_GID}

                # Clone GitHub repository with user context
                sudo -u $USERNAME git clone https://github.com/jiuntian/pytorch-mnist-example.git ${PROJECT_USER}/template
                if [ $? -eq 0 ]; then
                    echo "INFO::${FUNCNAME} ${GROUP} ${USERNAME}: Cloned template repo"
                else
                    echo "ERROR::${FUNCNAME} ${GROUP} ${USERNAME}: Failed to clone repository" 
                    return 1
                fi
                
                ln -sfT "/project/$GID" ${PROJECT_GROUP}
                restorecon -F -R ${PROJECT_GID} ${PROJECT_GROUP}
                echo "INFO::${FUNCNAME} ${GROUP}: created ${PROJECT_GID}"
            else
                echo "WARN::${FUNCNAME} ${GROUP}: ${PROJECT_GID} already exists"
            fi
        fi
        # We create the associated account in slurm
        /opt/software/slurm/bin/sacctmgr add account $GROUP -i &> /dev/null
        if [ $? -eq 0 ]; then
            echo "INFO::${FUNCNAME} ${GROUP}: SlurmDB account created"
        fi
        rmdir /var/lock/mkproject.$GROUP.lock
    fi
}

# return codes
# 0: project was correctly modified
# 1: context did not allow function to execute, retry later
# 2: not used
# 3: invalid arguments, do not retry
modproject() {
    local GROUP=$1
    local WITH_FOLDER=$2
    local USERNAMES="${@:3}"

    if [ -z "${GROUP}" ]; then
        echo "ERROR::${FUNCNAME}: group unspecified"
        return 3
    fi

    local PROJECT_GROUP="/project/$GROUP"
    # mkproject is currently running, we skip adding more folder under the project
    if [ -d /var/lock/mkproject.$GROUP.lock ]; then
        echo "ERROR::${FUNCNAME}: $GROUP $USERNAMES group folder is locked"
        return 1
    fi
    local GROUP_LINK=$(readlink /project/${GROUP})
    # mkproject has yet been ran for this group, skip it
    if [[ "${WITH_FOLDER}" == "true" ]]; then
        if [[ -z "${GROUP_LINK}" ]]; then
            echo "ERROR::${FUNCNAME}: $GROUP $USERNAMES mkproject has yet been ran for this group, skip it"
            return 1
        fi
    else
        if [[ $(/opt/software/slurm/bin/sacctmgr -n list account Name=${GROUP} | wc -l) -eq 0 ]]; then
            echo "ERROR::${FUNCNAME}: Slurm account does not exist"
            return 1
        fi
    fi
    # The operation that add users to a group would have operations with a uid.
    # If we found none, $USERNAMES will be empty, and it means we don't have
    # anything to add to Slurm and /project
    if [[ ! -z "${USERNAMES}" ]]; then
        if [ "$WITH_FOLDER" == "true" ]; then
            for USERNAME in $USERNAMES; do
                # Slurm needs the UID to be available via SSSD
                local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
                if [ -z "${USER_HOME}" ]; then
                    echo "ERROR::${FUNCNAME} ${USERNAME}: home path not defined"
                    return 1
                fi

                local USER_UID=$(SSS_NSS_USE_MEMCACHE=no id -u $USERNAME 2> /dev/null)
                if [ -z "${USER_UID}" ]; then
                    echo "ERROR::${FUNCNAME} ${USERNAME}: UID not defined"
                    return 1
                fi

                mkdir -p "${USER_HOME}/projects"
                chgrp "${USER_UID}" "${USER_HOME}/projects"
                chmod 0755 "${USER_HOME}/projects"
                ln -sfT "${PROJECT_GROUP}" "${USER_HOME}/projects/${GROUP}"

                local PROJECT_USER="${PROJECT_GROUP}/${USERNAME}"
                if [ ! -d "${PROJECT_USER}" ]; then
                    mkdir -p ${PROJECT_USER}
                    chown "${USER_UID}" "${PROJECT_USER}"
                    chmod 2700 "${PROJECT_USER}"
                    restorecon -F -R "${PROJECT_USER}"
                    echo "INFO::${FUNCNAME} ${GROUP} ${USERNAME}: created ${PROJECT_USER}"
                else
                    echo "WARN::${FUNCNAME} ${GROUP} ${USERNAME}: ${PROJECT_USER} already exists"
                fi
            done
        fi
        /opt/software/slurm/bin/sacctmgr add user ${USERNAMES} Account=${GROUP} -i &> /dev/null
        if [ $? -eq 0 ]; then
            echo "INFO::${FUNCNAME} ${GROUP}: ${USERNAMES} added to ${GROUP} in SlurmDB"
        fi
    else
        # If group has been modified but no uid were found in the log, it means
        # user(s) have been removed from the groups.
        # We identify which ones by comparing Slurm account with group.
        local SLURM_ACCOUNT=$(/opt/software/slurm/bin/sacctmgr list assoc account=$GROUP format=user --noheader -P | awk NF | sort)
        local USER_GROUP=$(kexec ipa group-show ${GROUP} --raw | grep -oP 'uid=\K([a-z0-9]*)' | sort)
        local USERNAMES=$(comm -2 -3 <(echo "$SLURM_ACCOUNT") <(echo "$USER_GROUP"))
        if [[ ! -z "$USERNAMES" ]]; then
            /opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i &> /dev/null
            if [ $? -eq 0 ]; then
                echo "INFO::${FUNCNAME} ${GROUP}: removed ${USERNAMES//[$'\n']/ } from ${GROUP} in SlurmDB"
            else
                echo "ERROR::${FUNCNAME} ${GROUP}: removing ${USERNAMES//[$'\n']/ } from ${GROUP} in SlurmDB"
            fi
            if [ "$WITH_FOLDER" == "true" ]; then
                for USERNAME in $USERNAMES; do
                    if id $USERNAME &> /dev/null; then
                        local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
                    else
                        local USER_HOME=$(kexec ipa user-show ${USERNAME} | grep -oP 'Home directory: \K(.*)$')
                    fi

                    if [ -z "${USER_HOME}" ]; then
                        echo "ERROR::${FUNCNAME} ${GROUP}: ${USERNAME} home path not defined"
                        return 1
                    fi

                    rm "${USER_HOME}/projects/$GROUP" &> /dev/null
                    if [ $? -eq 0 ]; then
                        echo "INFO::${FUNCNAME} ${GROUP}: removed symlink $USER_HOME/projects/$GROUP"
                    else
                        echo "ERROR::${FUNCNAME} ${GROUP}: could not remove symlink $USER_HOME/projects/$GROUP"
                        return 1
                    fi
                done
            fi
        else
            echo "WARN::${FUNCNAME} ${GROUP}: Could not find usernames to remove from ${GROUP}"
        fi
    fi
}

delproject() {
    local GROUP=$1
    local WITH_FOLDER=$2

    # A group has been removed.
    # Since we do not want to delete any data we only remove the
    # symlinks and remove the users from the slurm account.
    local USERNAMES=$(/opt/software/slurm/bin/sacctmgr list assoc account=$GROUP format=user --noheader -P | awk NF | sort)
    if [[ ! -z "$USERNAMES" ]]; then
        /opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i &> /dev/null
        if [ $? -eq 0 ]; then
            echo "INFO::${FUNCNAME}: removed ${USERNAMES} from ${GROUP} in SlurmDB"
        else
            echo "ERROR::${FUNCNAME}: could not remove ${USERNAME} from ${GROUP} in SlurmDB"
        fi
        if [ "$WITH_FOLDER" == "true" ]; then
            for USERNAME in $USERNAMES; do
                if id $USERNAME &> /dev/null; then
                    local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
                    local METHOD="getent/id"
                else
                    local USER_HOME=$(kexec ipa user-show ${USERNAME} | grep -oP 'Home directory: \K(.*)$')
                    local METHOD="ipa"
                fi

                if [ -z "${USER_HOME}" ]; then
                    echo "ERROR::${FUNCNAME} ${USERNAME}: home path not defined (${METHOD})"
                    return 1
                fi

                rm "${USER_HOME}/projects/$GROUP"
            done
        fi
    fi
}
