# volumes/

Placeholder for OPTIONAL bind mounts. By default the stack uses Docker-managed
named volumes (see `volumes:` in each compose file), which is the recommended
approach. If you prefer host-path bind mounts (e.g. for easy backups), point a
service at the matching folder here, e.g. in compose.yaml:

    elasticsearch:
      volumes:
        - ./volumes/elasticsearch:/usr/share/elasticsearch/data

Then fix ownership once so the container user can write:

    sudo chown -R 1000:0 volumes/elasticsearch volumes/kibana
