from kubernetes import client, config


def handle(req):
    """handle a request to the function
    Args:
        req (str): request body
    """

    config.load_incluster_config()

    group = "helm.fluxcd.io"
    version = "v1"
    plural = "helmreleases"
    api_instance = client.CustomObjectsApi()

    api_response = api_instance.list_cluster_custom_object(
        group=group,
        version=version,
        plural=plural)

    return json.dumps(api_response)