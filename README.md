# Receta para el despliegue de Kubernetes con Kubespray

Esta receta está basada en la de Ignacio Domínguez Martínez-Casanueva. La original está basada en un escenario sobre vnx. La idea es llevar este despliegue a un clúster físico donde levantar varios nodos de Kubernetes. El proyecto original se encuentra alojado en: https://github.com/giros-dit/vnx-kubespray

En primer lugar nos bajamos un zip donde se encuentran todos los ficheros que permiten el despliegue de kubespray. En él se incluyen tanto los ficheros para realizar el despliegue con ansible a la 
par que contiene un fichero xml en VNX que permite lanzar instancias virtuales en las que desplegar kubernetes. Tal caso no es el nuestro, ya que disponemos de 4 máquinas en las que realizar este despliegue.
No obstante, solo utilizaremos 3 máquinas: 1 nodo máster o de control y dos workers donde se alojarán los contenedores. La otra máquina se empleará para alojar OSM y conectarlo al clúster de Kubespray.
Esta conexión permitirá desplegar funciones de red contenerizadas.

```
wget http://idefix.dit.upm.es/download/vnx/examples/k8s/tutorial_kubespray-v01.tgz
```

```
tar -xvzf tutorial_kubespray-v01.tgz
```
Una vez extraídos todos los ficheros hay que realizar algunos ajustes en ellos. El principal archivo es el considerado inventario. En el archivo tutorial_kubespray-v01/ansible/inventory/inventory.ini hay que disponer de las siguientes líneas:


```
# ## Configure 'ip' variable to bind kubernetes services on a
# ## different ip than the default iface
# ## We should set etcd_member_name for etcd cluster. The node that is not a etcd member do not need to set the value, or can set the empty string value.
[all]
#k8s-master  ip=10.10.10.10 etcd_member_name=etcd1
pagoda1.dit.upm.es  ip=138.4.7.139 ansible_user=giros
pagoda2.dit.upm.es ip=138.4.7.140 ansible_user=giros
pagoda3.dit.upm.es ip=138.4.7.141 ansible_user=giros
r1 ip=138.4.7.129

# ## configure a bastion host if your nodes are not directly reachable
# bastion ansible_host=x.x.x.x ansible_user=some_user

[kube-master]
pagoda1.dit.upm.es

[etcd:children]
pagoda1.dit.upm.es

[kube-node]
pagoda2.dit.upm.es
pagoda3.dit.upm.es
#[calico-rr]

[k8s-cluster:children]
kube-master
kube-node
#calico-rr
```

Básicamente el cambio realizado es el de los nodos. Mientras que en el zip orginal este archivo está configurado para emplear las instancias generadas a través de VNX en este caso se configura para emplear las intancias físicas del departamento. Junto al nombre de estos hosts, se proporciona la dirección de ip de cada uno de ellos al igual que el usuario con el cual ansible accederá en estas computadoras.

Es obvio que previamente hay que configurar los hosts para que haya acceso ssh desde la máquina principal desde donde se lanza el proceso de instalación. En este caso dicha máquina es ajena a tal proceso.

Por un lado se generá claves shh en esta máquina mediante el comando *ssh-keygen*. 

Una vez generadas las claves, hacemos uso del comando *ssh-copy-id* con el cual se obtiene la clave pública generada previamente y se copia en los distintos servidores seleccionados. También se selecciona el usuario de dichos servidores con el cual se conectará a estos.

En el archivo ansible.cfg debemos cambiar la variable private_key_file con la siguiente línea:
```
private_key_file = /home/$USER/.ssh/id_rsa
```
En esta nueva variable se introduce la ruta a la clave privada generada con *ssh-keygen*


A parte de los permisos de acceso, se produce otro problema a la hora de hacer instalaciones con ansible. Normalmente, en estas instalaciones se puede preguntar por la contraseña del usuario ya que la mayoría de métodos los hace mediante el prefijo *sudo*. Para que esto no suponga un problema hay que dar permiso a nuestro usuario para que no se le requiera la contraseña. Esto se consigue modificando el fichero /etc/sudoers añadiendo la siguiente sentencia: *giros ALL=(ALL) NOPASSWD:ALL*



Otro de los cambios realizados es en el archivo ansible/inventory/group_vars/all.yaml. En el debemos activar el siguiente flag:

*etcd_kubeadm_enabled: true* 

Uno de los elementos a parametrizar a gusto es el del balanceador Metallb. En un principio este elemento está configurado para comunicarse mediante BGP, con lo cual se asume la necesidad de usar Calico como CNI y, además, establecer una configuración BGP para el router. En este caso no se tienen permisos de acceso para configurar dicho router. Al darse este caso, se obvia está configuración por defecto y se opta por una configuración normal, en la que se trata de asignar un rango de direcciones ips a este balanceador para que sea accesible desde el exterior. Cabría plantear si puede haber varios balanceadores. En un primer lugar se usa para acceder a los distintos servicios que se desplieguen bajo los cuales se encuentran los distintos pods que dan funcionalidad a nuestras aplicaciones. Por otro lado a la hora de conectar el Open Source Mano la idea es es conectarlo al cluster a través de la dirección ip de anunciamiento del api de Kubernetes. 


Todo este proceso se realiza mediante el comando root ya que así se especifica cuando se procede al despliegue: 

```
sudo time ansible-playbook --become --become-user=root site.yml

```
Usamos la sentencia become para indicar que queremos realizar los procesos con el comando sudo y que el usuario desde el que se realizan todos los métodos de instalación es el root. Es posible que al indicar esto último no sea necesaria la sentencia *--become*. En un primer momento se intentó realizar la instalación con el usuario giros pero había sentencias en algunos de los archivos de configuración que acaban dando fallo por problemas de permisos de acceso a directorios.



Otro de los cambios realizados es el de modificar el fichero site.yml dónde se alojan algunas de los roles que han de ser instalados en cada uno de los nodos indicados. Entre estos cambios se llamaba al router, al cual se le instala BIRD para permitir la configuración de red con BGP y Calico.  En este caso no se dispone de un router accesible, con lo cual está instalación no es posible. Además, esta modificación ya había supuesto problemas con el escenario virtual de VNX.

El fichero quedaría de la siguiente manera:

```
---

  - name: Include kubespray tasks
    include: kubespray/cluster.yml
    tags: kubespray

  - hosts: kube-master[0]
    roles:
      - metallb
    tags: metallb

  - hosts: kube-master[0]
    roles:
      - nginx-ingress
    tags: nginx-ingress
```


Finalmente, esta última modificación propuesta no ha sido realizada pero sería la manera de automatizar lo que en este proces ose ha hecho de forma manual. Una vez acaba el despliegue de ansible y kubernetes es instalado sigue el proceso de verificación de que todo está instalado y es funcional. El principal problema es que esta verificación y, por lo tanto, el uso de Kubernetes solo se permite desde el usuario *root*. Esto se debe a que en el resto de usuarios no hay acceso al fichero kubeconfig. Lo que se ha hecho en este caso es coger el fichero desde root y copiarlo en el usuario que interesa, a la par que se la da permisos a este usuario para poder acceder al cluster.

La otra manera de realizar este paso de forma automática es cambiar el fichero kubespray/roles/kubernetes/client/tasks/main.yml, cambiando el usuario para que el destino del fichero admin.conf esté en el usuario giros


```

- name: Copy admin kubeconfig to current/ansible become user home
  copy:
    src: "{{ kube_config_dir }}/admin.conf"
    dest: "{{ ansible_env.HOME | default('/root') }}/.kube/config"
    remote_src: yes
    mode: "0600"
    backup: yes
    
    
- name: Copy admin kubeconfig to current/ansible become user home
  copy:
    src: "{{ kube_config_dir }}/admin.conf"
    dest: "{{ ansible_env.HOME | default('/giros') }}/.kube/config"
    remote_src: yes
    mode: "0600"
    backup: yes

```


Es posible que haya que introducir más modificaciones en el caso de querer conectar OSM a este cluster de kubernetes. Esto se debe a que debe haber una dirección ip a la que OSM deba contactar. Por defecto, kubernetes está siendo ejecutado y escucha en la dirección localhost: 127.0.0.1:6443. Esto inhabilitaría la conexión con OSM. Es por eso que al lanzar kubespray hay que determinar en que dirección se escucha, modificando el valor de localhost que viene por defecto.

---
- name: Set kubeadm_discovery_address
  set_fact:
    kubeadm_discovery_address: >-
      {%- if "138.4.7.139" in kube_apiserver_endpoint or "localhost" in kube_apiserver_endpoint -%}
      
La forma manual sería una vez hecho el despliegue crear un archivo yaml kubeconfig propio al que llamar. 
```
kubeadm init --config kubeconfig.yaml
```

Otra forma de automatizarlo que parece más correctar es indagar en la configuración de kubeadm creada. Se usa un fichero por defecto que establece las variables de configuración de kubeadm y del nodo de control. Entre estas variables está de adverisement. Con lo cual puede que lo mejor sea cambiar el valor de tal dirección


Finalmente, hay que integrar este cluster junto al de OSM. Para añadir este cluster es necesario crear una nube de juju de tipo k8s y un controlador para este nuevo cluster. Para ello hay que cambiar el archivo config en el directorio .kube por el kubeconfig del cluster que queremos añadir y rellenar una variable de entorno que apunte a este fichero:

```
export $KUBECONFIG = .kube/config
sudo cp kubeconfig_cluster.yaml .kube/config
```


Es tiempo de crear un controlador con el comando bootstrap

```
juju bootstrap kubespray
```

Ahora, desde pagoda 1 hay que copiar el siguente contenido en un script sh y ejecutarlo para crear un volumen persistente

```
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
```

```
chmod +x install_k8s_storageclass.sh
./install_k8s_storageclass
```


Una vez generado dicho volumen volvemos a la máquina donde esta corriendo osm y juju para crear la nube de juju y posteriormetne llamar al comando de osm osm k8scluster-add para unir el cluster a osm

```
juju add-k8s kubespray --controller kubespray 
```

Finalmente, volvemos a cambiar el archivo de configuración kubeconfig del directorio .kube por el de OSM. Este cambio de fichero funciona como un switch de api de kubernetes. Dependiendo del kubeconfig nuestros comandos kubectl llamarán a la api de uno o de otro cluster. En este caso ahora nos interesa voler a comunicarnos con la api del nodo osm para poder llamar al comando osm k8scluster-add.

### Receta rápida

Finalmente se ofrece una receta rápida con las instrucciones para el despliegue de Kubernetes:

```
cd tutorial_kubespray/ansible/kubespray
sudo pip3 install -r requirements.txt
cd tutorial_kubespray/ansible
sudo time ansible-playbook --become --become-user=root site.yml
```

En el caso de resetear el clúster y sus configuraciones se debería hacer uso del siguiente comando que recurre al archivo reset.yaml donde están especificadas las desconfiguraciones por defecto a llevar a cabo.

```
sudo time ansible-playbook --become --become-user=root ./kubespray/reset.yaml
```


