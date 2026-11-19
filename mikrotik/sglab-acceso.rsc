# Permite que los clientes del laboratorio lleguen a SGLAB a traves del MikroTik.
# Solo hace falta si clientes y servidor estan en redes distintas: en la misma
# subred el trafico no pasa por el firewall del router.
#
# 1. Ajustar los tres valores de abajo.
# 2. Importar: /import file-name=sglab-acceso.rsc
# 3. En IP > Firewall > Filter, mover la regla por encima de cualquier "drop" del
#    chain forward. Las respuestas requieren la regla habitual que acepta
#    connection-state=established,related.
:local redClientes "192.168.2.0/24"
:local servidorSglab "192.168.2.46"
:local puertoWeb "8080"

/ip firewall filter add chain=forward action=accept protocol=tcp \
    src-address=$redClientes dst-address=$servidorSglab dst-port=$puertoWeb \
    comment="SGLAB: clientes hacia la API de registro"
