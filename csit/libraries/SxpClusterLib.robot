*** Settings ***
Documentation     Library containing Keywords used for SXP cluster testing
Library           RequestsLibrary
Library           ./Sxp.py
Resource          ./SxpLib.robot
Resource          ./ClusterManagement.robot
Variables         ../variables/Variables.py

*** Variables ***
@{SHARD_OPER_LIST}    inventory    topology    default    entity-ownership
@{SHARD_CONF_LIST}    inventory    topology    default
${DEVICE_SESSION}    device_1
${DEVICE_NODE_ID}    1.1.1.1
${CLUSTER_NODE_ID}    2.2.2.2

*** Keywords ***
Setup SXP Cluster Session
    [Documentation]    Create sessions asociated with SXP cluster setup
    Wait Until Keyword Succeeds    120    10    Prepare SSH Keys On Karaf    ${TOOLS_SYSTEM_IP}    ${TOOLS_SYSTEM_USER}    ${TOOLS_SYSTEM_PASSWORD}
    ...    ${TOOLS_SYSTEM_PROMPT}    /tmp
    Setup SXP Session    ${DEVICE_SESSION}    ${TOOLS_SYSTEM_IP}
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    Wait Until Keyword Succeeds    120    10    Prepare SSH Keys On Karaf    ${ODL_SYSTEM_${i+1}_IP}
    \    Setup SXP Session    controller${i+1}    ${ODL_SYSTEM_${i+1}_IP}
    ClusterManagement_Setup

Clean SXP Cluster Session
    [Documentation]    Clean sessions asociated with SXP cluster setup
    Flush_Iptables_From_List_Or_All
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    Wait Until Keyword Succeeds    240    1    Sync_Status_Should_Be_True    ${i+1}
    Clean SXP Session

Check Shards Status
    [Documentation]    Check Status for all shards in SXP application.
    ClusterManagement.Check_Cluster_Is_In_Sync
    ClusterManagement.Verify_Leader_Exists_For_Each_Shard    shard_name_list=${SHARD_OPER_LIST}    shard_type=operational
    ClusterManagement.Verify_Leader_Exists_For_Each_Shard    shard_name_list=${SHARD_CONF_LIST}    shard_type=config

Setup SXP Cluster
    [Arguments]    ${peer_mode}=listener
    [Documentation]    Setup and connect SXP cluster topology
    Add Node    ${DEVICE_NODE_ID}    ip=0.0.0.0    session=${DEVICE_SESSION}
    Wait Until Keyword Succeeds    20    1    Check Node Started    ${DEVICE_NODE_ID}    session=${DEVICE_SESSION}    system=${TOOLS_SYSTEM_IP}
    ...    ip=${EMPTY}
    ${cluster_mode}    Get Opposing Mode    ${peer_mode}
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    Add Connection    version4    ${peer_mode}    ${ODL_SYSTEM_${i+1}_IP}    64999    ${DEVICE_NODE_ID}
    \    ...    session=${DEVICE_SESSION}
    ${controller_id}    Get Any Controller
    Add Node    ${CLUSTER_NODE_ID}    ip=0.0.0.0    session=controller${controller_id}
    Wait Until Keyword Succeeds    20    1    Check Cluster Node started    ${CLUSTER_NODE_ID}
    Add Connection    version4    ${cluster_mode}    ${TOOLS_SYSTEM_IP}    64999    ${CLUSTER_NODE_ID}    session=controller${controller_id}
    Wait Until Keyword Succeeds    120    1    Check Device is Connected    ${DEVICE_NODE_ID}    session=${DEVICE_SESSION}

Clean SXP Cluster
    [Documentation]    Disconnect SXP cluster topology
    Flush_Iptables_From_List_Or_All
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    Wait Until Keyword Succeeds    240    1    Sync_Status_Should_Be_True    ${i+1}
    ${controller_index}    Get Active Controller
    Delete Node    ${DEVICE_NODE_ID}    session=${DEVICE_SESSION}
    Delete Node    ${CLUSTER_NODE_ID}    session=controller${controller_index}

Check Cluster Node started
    [Arguments]    ${node}    ${port}=64999    ${ip}=${EMPTY}
    [Documentation]    Verify that SxpNode has data written to Operational datastore and Node is running on one of cluster nodes
    ${started}    Set Variable    ${False}
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    ${rc}    Run Command On Remote System    ${ODL_SYSTEM_${i+1}_IP}    netstat -tln | grep -q ${ip}:${port} && echo 0 || echo 1    ${ODL_SYSTEM_USER}    ${ODL_SYSTEM_PASSWORD}
    \    ...    prompt=${ODL_SYSTEM_PROMPT}
    \    ${started}    Set Variable If    '${rc}' == '0'    ${True}    ${started}
    Should Be True    ${started}

Check Device is Connected
    [Arguments]    ${node}    ${version}=version4    ${port}=64999    ${session}=session
    [Documentation]    Checks if SXP device is connected to at least one cluster node
    ${is_connected}    Set Variable    ${False}
    ${resp}    Get Connections    node=${node}    session=${session}
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    ${follower}    Find Connection    ${resp}    ${version}    any    ${ODL_SYSTEM_${i+1}_IP}
    \    ...    ${port}    on
    \    ${is_connected}    Run Keyword If    ${follower}    Set Variable    ${True}
    \    ...    ELSE    Set Variable    ${is_connected}
    Should Be True    ${is_connected}

Check Cluster is Connected
    [Arguments]    ${node}    ${version}=version4    ${port}=64999    ${mode}=speaker    ${session}=session
    [Documentation]    Checks if SXP device is connected to at least one cluster node
    ${resp}    Get Connections    node=${node}    session=${session}
    Should Contain Connection    ${resp}    ${TOOLS_SYSTEM_IP}    ${port}    ${mode}    ${version}

Get Active Controller
    [Documentation]    Find cluster controller that is marked as leader for SXP service in cluster
    @{votes}    Create List
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    ${resp}    RequestsLibrary.Get Request    controller${i+1}    /restconf/operational/entity-owners:entity-owners
    \    Continue For Loop If    ${resp.status_code} != 200
    \    ${controller}    Get Active Controller From Json    ${resp.content}    SxpControllerInstance
    \    Append To List    ${votes}    ${controller}
    ${length}    Get Length    ${votes}
    Should Not Be Equal As Integers    ${length}    0
    ${active_controller}    Evaluate    collections.Counter(${votes}).most_common(1)[0][0]    collections
    [Return]    ${active_controller}

Get Inactive Controller
    [Documentation]    Find cluster controller that is not marked as leader for SXP service in cluster
    ${active_controller}    Get Active Controller
    ${controller}    Evaluate    random.choice( filter( lambda i: i!=${active_controller}, range(1, ${NUM_ODL_SYSTEM} + 1)))    random
    [Return]    ${controller}

Get Any Controller
    [Documentation]    Get any controller from cluster range
    ${follower}    Evaluate    random.choice( range(1, ${NUM_ODL_SYSTEM} + 1))    random
    [Return]    ${follower}

Map Followers To Mac Addresses
    [Documentation]    Creates Map containing ODL_SYSTEM_IP to corresponding MAC-ADDRESS
    ${mac_addresses}    create dictionary
    : FOR    ${i}    IN RANGE    ${NUM_ODL_SYSTEM}
    \    ${mac_address}    Find Mac Address Of Ip Address    ${ODL_SYSTEM_${i+1}_IP}
    \    Set To Dictionary    ${mac_addresses}    ${ODL_SYSTEM_${i+1}_IP}    ${mac_address}
    Log    ${mac_addresses}
    [Return]    ${mac_addresses}

Find Mac Address Of Ip Address
    [Arguments]    ${ip}
    [Documentation]    Finds out MAC-ADDRESS of specified IP by pinging it from TOOLS_SYSTEM machine
    ${mac_address}    Run Command On Remote System    ${TOOLS_SYSTEM_IP}    ping -c 1 -W 1 ${ip} >/dev/null && arp -n | grep ${ip} | awk '{print $3}'    ${TOOLS_SYSTEM_USER}    ${TOOLS_SYSTEM_PASSWORD}
    [Return]    ${mac_address}

Ip Addres Should Not Be Routed To Follower
    [Arguments]    ${mac_addresses}    ${ip_address}    ${follower_index}
    [Documentation]    Verify that IP-ADDRESS is not routed to follower specified by ID
    ${mac_address_assigned}    Get From Dictionary    ${mac_addresses}    ${ODL_SYSTEM_${follower_index}_IP}
    ${mac_address_resolved}    Find Mac Address Of Ip Address    ${ip_address}
    Should Not Be Equal As Strings    ${mac_address_assigned}    ${mac_address_resolved}

Ip Addres Should Be Routed To Follower
    [Arguments]    ${mac_addresses}    ${ip_address}    ${follower_index}
    [Documentation]    Verify that IP-ADDRESS is routed to follower specified by ID
    ${mac_address_assigned}    Get From Dictionary    ${mac_addresses}    ${ODL_SYSTEM_${follower_index}_IP}
    ${mac_address_resolved}    Find Mac Address Of Ip Address    ${ip_address}
    Should Not Be Empty    ${mac_address_resolved}
    Should Be Equal As Strings    ${mac_address_assigned}    ${mac_address_resolved}

Shutdown Tools Node
    [Arguments]    ${ip_address}=${TOOLS_SYSTEM_2_IP}    ${user}=${TOOLS_SYSTEM_USER}    ${passwd}=${TOOLS_SYSTEM_PASSWORD}
    [Documentation]    Shutdown Tools node to avoid conflict in resolving virtual ip that is overlaping that node.
    ${rc}    Run And Return Rc    ping -q -c 3 ${ip_address}
    ${stdout}    Run Keyword And Return If    ${rc} == 0    Run Command On Remote System    ${ip_address}    sudo shutdown -P 0    ${user}
    ...    ${passwd}
    Log    ${stdout}
