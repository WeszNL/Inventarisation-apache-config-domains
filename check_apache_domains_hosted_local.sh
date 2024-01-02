#!/bin/bash

# Specify the directory containing Apache configuration files
conf_directory="/etc/apache2/sites-enabled"

# Specify the network interface(s) used on your server, eg: "etho" "ens33"
network_interface="eth0"

# Specify the output CSV file
output_csv="domain_info.csv"

# Ensure the directory exists
if [ ! -d "$conf_directory" ]; then
    echo "Error: Directory not found."
    exit 1
fi

# Extract domain names from ServerName and ServerAlias directives
extract_domains() {
    awk '/^[^#]*ServerName/ { print $2 }' "$1"
    awk '/^[^#]*ServerAlias/ { for (i=2; i<=NF; i++) print $i }' "$1" | tr -d ' '
}

# Perform a dig A lookup for a domain and display the IP
perform_dns_lookup() {
    domain="$1"
    dig +short A "$domain"
}

# Perform a reverse DNS lookup for an IP and display the hostname
reverse_dns_lookup() {
    ip="$1"
    result=$(dig -x "$ip" +short)
    if [ -z "$result" ]; then
        echo "N/A"
    else
        echo "$result"
    fi
}

# Get the IP addresses configured on the server
configured_ips=($(ip -o -4 addr show dev "$network_interface" | awk '{print $4}' | cut -d'/' -f1))

# Create or overwrite the output CSV file
echo "Config File,Domain Name,Resolved IP,Hostname,Hosted on Server" > "$output_csv"

# Associative array to track processed domains
declare -A processed_domains

# Process each config file and generate a list of domains and IPs
for conf_file in "$conf_directory"/*; do
    domains=($(extract_domains "$conf_file"))

    # Skip if no valid domains are found
    if [ ${#domains[@]} -eq 0 ]; then
        continue
    fi

    for domain in "${domains[@]}"; do
        # Check if the domain has been processed already
        if [ -n "${processed_domains[$domain]}" ]; then
            continue
        fi

        # Mark the domain as processed
        processed_domains["$domain"]=1

        # Perform DNS lookup and reverse DNS lookup
        ip_addresses=($(perform_dns_lookup "$domain"))

        for ip in "${ip_addresses[@]}"; do
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                hosted_on_server="No"
                if [[ " ${configured_ips[@]} " =~ " $ip " ]]; then
                    hosted_on_server="Yes"
                fi
                hostname=$(reverse_dns_lookup "$ip")
            else
                hosted_on_server="No"
                hostname=""
            fi

            # Append data to the CSV file
            echo "$conf_file,$domain,$ip,$hostname,$hosted_on_server" >> "$output_csv"
        done
    done
done

echo "CSV file generated: $output_csv"
