. scripts/env.sh

function download_aeron_jars() {
    # Get the version number from the input parameter
    local version="${VERSION}"
    
    # Define the download directory (modify as needed)
    local download_dir="./"
    
    # Define the jar filenames
    local agent_jar="aeron-agent-${version}.jar"
    local all_jar="aeron-all-${version}.jar"
    
    # Check if both jars exist in the download directory
    if [[ ! -f "$download_dir/$agent_jar" || ! -f "$download_dir/$all_jar" ]]; then
        echo "Downloading Aeron jars for version: $version"
        
        # Download agent jar
        wget -q -O "$download_dir/$agent_jar" https://repo1.maven.org/maven2/io/aeron/aeron-agent/$version/$agent_jar
        
        # Download all jar
        wget -q -O "$download_dir/$all_jar" https://repo1.maven.org/maven2/io/aeron/aeron-all/$version/$all_jar
        
        echo "Download completed."
    else
        echo "Aeron jars for version $version already exist."
    fi
}

download_aeron_jars