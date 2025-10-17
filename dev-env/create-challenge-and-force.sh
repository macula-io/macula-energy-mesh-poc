#! /bin/bash
domain=swarm-wars.ai
echo "Creating challenge for" ${domain}
sleep 5
docker compose exec certbot mkdir -p /var/www/certbot/${domain}/.well-known/acme-challenge/
docker compose exec certbot sh -c "echo $(date) > /var/www/certbot/${domain}/.well-known/acme-challenge/test-token.txt"
docker compose exec certbot certbot renew --no-random-sleep-on-renew --force-renew

