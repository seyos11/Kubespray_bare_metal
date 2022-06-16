#!/bin/bash
function install_k8s_storageclass() {
    echo "Installing open-iscsi"
    sudo apt-get update
    sudo apt-get install open-iscsi
    sudo systemctl enable --now iscsid
    echo "Installing OpenEBS"
    helm repo add openebs https://openebs.github.io/charts
    helm repo update
    helm install --create-namespace --namespace openebs openebs openebs/openebs --version 3.1.0
    helm ls -n openebs
    local storageclass_timeout=400
    local counter=0
    local storageclass_ready=""
    echo "Waiting for storageclass"
    while (( counter < storageclass_timeout ))
    do
        kubectl get storageclass openebs-hostpath &> /dev/null

        if [ $? -eq 0 ] ; then
            echo "Storageclass available"
            storageclass_ready="y"
            break
        else
            counter=$((counter + 15))
            sleep 15
        fi
    done
    [ -n "$storageclass_ready" ] || FATAL "Storageclass not ready after $storageclass_timeout seconds. Cannot install openebs"
    kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}
install_k8s_storageclass()
