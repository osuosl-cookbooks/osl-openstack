execute 'copy self-signed ca-cert' do
  command <<-EOF
    cat /etc/pki/tls/certs/wildcard-bundle.crt >> \
      /etc/ssl/certs/ca-bundle.crt && touch /tmp/cacert
  EOF
  creates '/tmp/cacert'
end
