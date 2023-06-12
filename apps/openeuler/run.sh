#!/bin/bash


function usage(){
  echo """Usage:
  $(basename $0) [option]...
Options:
  -f|--docker-file-path      dockerfile path
  -n|--image-name   
  -t|--image-tag     
  -h|--help         print help information
 """
}


function show_usage(){

    GETOPT_ARGS=$(getopt -o f:n:t:h:: -al docker-file-path:,image-name:,image-tag:, help -- "$@")
    # eval set -- "${GETOPT_ARGS}"
    
    #获取参数
    while [ -n "$1" ]

    do
        case "$1" in
            
            -f|--docker-file-path) opt_dockerfile_path=$2 ; shift 2;;
            -n|--image-name) opt_dockerimage=$2; shift 2;;
            -t|--image-tag) opt_dockertag=$2; shift 2;;
            -h|--h|--help) usage shift 1 ;;
            --) break ;;
            *) echo $1,$2; break ;;
        esac
    done
    echo $opt_dockerfile_path
    if [[ -z $opt_localrepo || -z $opt_url || -z $opt_backupdir || -z $opt_webdir ]]; then
            echo $usage
            echo "opt_dockerfile_path: $opt_dockerfile_path , opt_dockerimage: $opt_dockerimage , opt_dockertag: $opt_dockertag"
            exit 0
    fi
}



function build_dockerfile(){
    #  echo "opt_dockerfile_path: $opt_dockerfile_path , opt_dockerimage: $opt_dockerimage , opt_dockertag: $opt_dockertag"
    docker build -f ${docker_file_path} -t ${image_name}:${image_tag} .

}


function main(){
    show_usage $@
    build_dockerfile
}

main $@