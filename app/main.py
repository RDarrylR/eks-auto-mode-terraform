from fastapi import FastAPI
import os
import time
import threading

app = FastAPI(title="EKS Auto Mode Demo")

# Memory stress storage (held across requests until released)
_stress_blocks = []
_stress_lock = threading.Lock()


def _get_node_info():
    """Fetch node labels via Kubernetes API to show Auto Mode scheduling decisions."""
    try:
        from kubernetes import client, config
        config.load_incluster_config()
        v1 = client.CoreV1Api()

        node_name = os.getenv("NODE_NAME")
        if not node_name:
            return {"error": "NODE_NAME not set - add downward API to deployment"}

        node = v1.read_node(node_name)
        labels = node.metadata.labels or {}

        return {
            "node_name": node_name,
            "instance_type": labels.get("node.kubernetes.io/instance-type", "unknown"),
            "capacity_type": labels.get("karpenter.sh/capacity-type", "unknown"),
            "nodepool": labels.get("karpenter.sh/nodepool", "unknown"),
            "zone": labels.get("topology.kubernetes.io/zone", "unknown"),
            "arch": labels.get("kubernetes.io/arch", "unknown"),
            "compute_type": labels.get("eks.amazonaws.com/compute-type", "unknown"),
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/health")
def health():
    return {"status": "healthy", "node": os.getenv("HOSTNAME", "unknown")}


@app.get("/info")
def info():
    """Pod and node details including Auto Mode scheduling decisions.

    Shows which instance type Karpenter selected, whether the node is
    Spot or On-Demand, which NodePool it belongs to, and the AZ.
    """
    node_info = _get_node_info()
    return {
        "pod": {
            "name": os.getenv("POD_NAME", "unknown"),
            "namespace": os.getenv("POD_NAMESPACE", "unknown"),
            "ip": os.getenv("POD_IP", "unknown"),
            "service_account": os.getenv("POD_SERVICE_ACCOUNT", "unknown"),
        },
        "node": node_info,
    }


@app.get("/compute/{iterations}")
def compute(iterations: int = 10000):
    """CPU-intensive endpoint for scaling demos. Higher iterations = more CPU load."""
    total = 0
    for i in range(min(iterations, 1000000)):
        total += i * i
    return {
        "result": total,
        "iterations": iterations,
        "node": os.getenv("HOSTNAME", "unknown"),
    }


@app.get("/stress/{mb}")
def stress(mb: int = 64, seconds: int = 30):
    """Allocate memory to demonstrate memory pressure.

    Holds the allocation for `seconds` (query param, default 30) then releases.
    Capped at 512 MB and 300 seconds to avoid OOMKill.
    """
    mb = min(mb, 512)
    seconds = min(seconds, 300)

    block = bytearray(mb * 1024 * 1024)
    # Touch every page to force physical allocation
    for i in range(0, len(block), 4096):
        block[i] = 1

    with _stress_lock:
        _stress_blocks.append(block)

    def release():
        time.sleep(seconds)
        with _stress_lock:
            try:
                _stress_blocks.remove(block)
            except ValueError:
                pass

    threading.Thread(target=release, daemon=True).start()

    return {
        "allocated_mb": mb,
        "hold_seconds": seconds,
        "active_stress_blocks": len(_stress_blocks),
        "node": os.getenv("HOSTNAME", "unknown"),
    }
