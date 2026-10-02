// Deployment pipeline: installs Apache2 (httpd) on the Vagrant/VirtualBox VM,
// deploys the site, generates fake 4xx/5xx requests and analyses the Apache logs.
// Jenkins (Docker) reaches the VM through the ports Vagrant forwards on the Mac.
pipeline {
    agent any

    parameters {
        string(name: 'VM_HOST', defaultValue: 'host.docker.internal', description: 'Address of the target VM (from the Jenkins container)')
        string(name: 'VM_SSH_PORT', defaultValue: '2223', description: 'SSH port forwarded by Vagrant')
        string(name: 'VM_HTTP_PORT', defaultValue: '8081', description: 'HTTP port forwarded by Vagrant')
        booleanParam(name: 'GENERATE_ERRORS', defaultValue: true, description: 'Send fake requests that produce 4xx/5xx responses')
        booleanParam(name: 'FAIL_ON_5XX', defaultValue: false, description: 'Mark the build UNSTABLE when 5xx errors are found in the logs')
    }

    options {
        timestamps()
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        // Explicit mapping: on the very first run of an SCM job, parameters are
        // not yet exported to the shell environment.
        VM_HOST      = "${params.VM_HOST}"
        VM_SSH_PORT  = "${params.VM_SSH_PORT}"
        VM_HTTP_PORT = "${params.VM_HTTP_PORT}"
        SSH_OPTS = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10'
        SITE_URL = "http://${params.VM_HOST}:${params.VM_HTTP_PORT}"
        REPORT   = 'apache-log-report.txt'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'git log -1 --oneline'
            }
        }

        stage('Check VM connection') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'vm-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                    sh '''
                        ssh $SSH_OPTS -i "$SSH_KEY" -p "$VM_SSH_PORT" "$SSH_USER@$VM_HOST" \
                            'hostname; . /etc/os-release; echo "$PRETTY_NAME"; uptime'
                    '''
                }
            }
        }

        stage('Install Apache2') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'vm-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                    sh '''
                        ssh $SSH_OPTS -i "$SSH_KEY" -p "$VM_SSH_PORT" "$SSH_USER@$VM_HOST" '
                            set -e
                            export DEBIAN_FRONTEND=noninteractive
                            sudo apt-get update -qq
                            sudo apt-get install -y -qq apache2 curl
                            sudo a2enmod -q rewrite cgid
                            sudo systemctl enable --now apache2
                            apache2 -v
                        '
                    '''
                }
            }
        }

        stage('Deploy site') {
            steps {
                sh 'sed -i "s/__BUILD__/${JOB_NAME} #${BUILD_NUMBER} ($(git rev-parse --short HEAD))/" site/index.html'
                withCredentials([sshUserPrivateKey(credentialsId: 'vm-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                    sh '''
                        scp $SSH_OPTS -i "$SSH_KEY" -P "$VM_SSH_PORT" -r \
                            apache/lab-site.conf site scripts/check_logs.sh "$SSH_USER@$VM_HOST:/tmp/"
                        ssh $SSH_OPTS -i "$SSH_KEY" -p "$VM_SSH_PORT" "$SSH_USER@$VM_HOST" '
                            set -e
                            sudo install -d /var/www/lab /var/www/lab-cgi
                            sudo install -m 644 /tmp/site/index.html /var/www/lab/index.html
                            sudo install -m 755 /tmp/site/cgi-bin/broken.cgi /var/www/lab-cgi/broken.cgi
                            sudo install -m 755 /tmp/check_logs.sh /usr/local/bin/check_apache_logs
                            sudo install -m 644 /tmp/lab-site.conf /etc/apache2/sites-available/lab-site.conf
                            sudo a2dissite -q 000-default || true
                            sudo a2ensite -q lab-site
                            sudo apache2ctl configtest
                            sudo systemctl restart apache2   # restart (not reload) so newly enabled modules like cgid start
                            rm -rf /tmp/site /tmp/lab-site.conf /tmp/check_logs.sh
                        '
                    '''
                }
            }
        }

        stage('Smoke test') {
            steps {
                sh '''
                    code=$(curl -s -o page.html -w '%{http_code}' "$SITE_URL/")
                    echo "GET / -> $code"
                    test "$code" = 200
                    grep -q "Apache2 deployed by Jenkins" page.html
                '''
            }
        }

        stage('Generate fake errors') {
            when { expression { params.GENERATE_ERRORS } }
            steps {
                sh '''
                    req() { printf '%-45s -> %s\\n' "$*" "$(curl -s -o /dev/null -w '%{http_code}' "$@")"; }
                    req "$SITE_URL/does-not-exist.html"                 # 404
                    req "$SITE_URL/wp-login.php"                        # 404
                    req "$SITE_URL/private/"                            # 403
                    req -X DELETE "$SITE_URL/index.html"                # 405
                    req -H 'Host:' "$SITE_URL/"                         # 400 (HTTP/1.1 without Host)
                    req --path-as-is "$SITE_URL/../../etc/passwd"       # 400
                    req "$SITE_URL/old-page"                            # 410
                    req "$SITE_URL/cgi-bin/broken.cgi"                  # 500
                    req "$SITE_URL/maintenance"                         # 503
                '''
            }
        }

        stage('Analyse Apache logs') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'vm-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                    sh '''
                        ssh $SSH_OPTS -i "$SSH_KEY" -p "$VM_SSH_PORT" "$SSH_USER@$VM_HOST" \
                            'sudo check_apache_logs /var/log/apache2/access.log /var/log/apache2/error.log' | tee "$REPORT"
                    '''
                }
                script {
                    // Last line looks like: SUMMARY total=17 4xx=8 5xx=2
                    def summary = readFile(env.REPORT).readLines().find { it.startsWith('SUMMARY') } ?: 'SUMMARY'
                    def counts = summary.tokenize(' ').drop(1).collectEntries { it.tokenize('=') }
                    int c4 = (counts['4xx'] ?: '0') as int
                    int c5 = (counts['5xx'] ?: '0') as int
                    currentBuild.description = "4xx: ${c4}, 5xx: ${c5}"
                    echo "Found ${c4} client errors (4xx) and ${c5} server errors (5xx)"
                    if (params.FAIL_ON_5XX && c5 > 0) {
                        unstable("${c5} 5xx errors found in Apache access log")
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'apache-log-report.txt', allowEmptyArchive: true
        }
        success {
            echo "Apache is running: http://localhost:${params.VM_HTTP_PORT}/ (from the Mac)"
        }
        cleanup {
            cleanWs()
        }
    }
}
