{
  "hosts": ["kvm01", "kvm02", "kvm03", "kvm04", "kvm05", "kvm06"],
  "_meta": {
    "hosts": {
      "kvm01": {
        "labels": {
          "location": "dc1",
          "type": "web"
        }
      },
      "kvm02": {
        "labels": {
          "location": "dc1",
          "type": "db"
        }
      },
      "kvm03": {
        "labels": {
          "location": "dc2",
          "type": "web"
        }
      },
      "kvm04": {
        "labels": {
          "location": "dc2",
          "type": "db"
        }
      },
      "kvm05": {
        "labels": {
          "location": "dc3",
          "type": "web"
        }
      },
      "kvm06": {
        "labels": {
          "location": "dc3",
          "type": "db"
        }
      }
    }
  }
}
