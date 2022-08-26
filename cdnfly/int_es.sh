es_dir=$1
if [[  `echo $es_dir | grep -E "^/"` == "" ]];then
    echo "please input a valid dir."
    exit 1
fi 

if [[ $es_dir == "/" ]];then
    echo "es_dir eq / "
    exit 1
fi

eval `grep "VERSION_NUM" /opt/cdnfly/master/conf/config.py`

sed -i "s#path.data.*#path.data: $es_dir#g" /etc/elasticsearch/elasticsearch.yml
mkdir -p $es_dir
chown -R elasticsearch $es_dir

service elasticsearch stop
iptables -I INPUT -p tcp --dport 9200 -j DROP
iptables -I INPUT -p tcp -s 127.0.0.1 -j ACCEPT
es_path=`awk '/path.data/{print $2}' /etc/elasticsearch/elasticsearch.yml`
if [[ $es_path == "" ]];then
    echo "empty es_path"
    exit 1
fi

if [[ $es_path == "/" ]];then
    echo "es_path eq / "
    exit 1
fi

rm -rf $es_path/nodes
password=`awk -F'=' '/LOG_PWD/{gsub("\"","",$2);print $2}' /opt/cdnfly/master/conf/config.py`
echo $password | /usr/share/elasticsearch/bin/elasticsearch-keystore add -xf bootstrap.password
service elasticsearch start
sleep 5
curl -H "Content-Type:application/json" -XPOST -u elastic:$password 'http://127.0.0.1:9200/_xpack/security/user/elastic/_password' -d "{ \"password\" : \"$password\" }"

curl -u elastic:$password -X PUT "127.0.0.1:9200/_ilm/policy/access_log_policy" -H 'Content-Type: application/json' -d'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
	    "max_size": "200gb",
            "max_age": "1d" 
          }
        }
      },
      "delete": {
        "min_age": "7d",
        "actions": {
          "delete": {} 
        }
      }
    }
  }
}
'

curl -u elastic:$password  -X PUT "127.0.0.1:9200/_ilm/policy/node_log_policy" -H 'Content-Type: application/json' -d'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_age": "1d" 
          }
        }
      },
      "delete": {
        "min_age": "7d",
        "actions": {
          "delete": {} 
        }
      }
    }
  }
}
'

# 从50006版本开始新增server_port
if [[ $VERSION_NUM -ge 50006 ]];then

  curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/http_access_template" -H 'Content-Type: application/json' -d'
  {
    "mappings": {
      "properties": {
        "nid":    { "type": "keyword" },  
        "uid":    { "type": "keyword" },  
        "upid":    { "type": "keyword" },  
        "time":   { "type": "date"  ,"format":"dd/MMM/yyyy:HH:mm:ss Z"},
        "addr":  { "type": "keyword"  }, 
        "method":  { "type": "text" , "index":false }, 
        "scheme":  { "type": "keyword"  }, 
        "host":  { "type": "keyword"  }, 
        "server_port":  { "type": "keyword"  }, 
        "req_uri":  { "type": "keyword"  }, 
        "protocol":  { "type": "text" , "index":false }, 
        "status":  { "type": "keyword"  }, 
        "bytes_sent":  { "type": "integer"  }, 
        "referer":  { "type": "keyword"  }, 
        "user_agent":  { "type": "text" , "index":false }, 
        "content_type":  { "type": "text" , "index":false }, 
        "up_resp_time":  { "type": "float" , "index":false,"ignore_malformed": true }, 
        "cache_status":  { "type": "keyword"  }, 
        "up_recv":  { "type": "integer", "index":false,"ignore_malformed": true  }
      }
    },  
    "index_patterns": ["http_access-*"], 
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "access_log_policy", 
      "index.lifecycle.rollover_alias": "http_access"
    }
  }
  '
else 
  curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/http_access_template" -H 'Content-Type: application/json' -d'
  {
    "mappings": {
      "properties": {
        "nid":    { "type": "keyword" },  
        "uid":    { "type": "keyword" },  
        "upid":    { "type": "keyword" },  
        "time":   { "type": "date"  ,"format":"dd/MMM/yyyy:HH:mm:ss Z"},
        "addr":  { "type": "keyword"  }, 
        "method":  { "type": "text" , "index":false }, 
        "scheme":  { "type": "keyword"  }, 
        "host":  { "type": "keyword"  }, 
        "req_uri":  { "type": "keyword"  }, 
        "protocol":  { "type": "text" , "index":false }, 
        "status":  { "type": "keyword"  }, 
        "bytes_sent":  { "type": "integer"  }, 
        "referer":  { "type": "keyword"  }, 
        "user_agent":  { "type": "text" , "index":false }, 
        "content_type":  { "type": "text" , "index":false }, 
        "up_resp_time":  { "type": "float" , "index":false,"ignore_malformed": true }, 
        "cache_status":  { "type": "keyword"  }, 
        "up_recv":  { "type": "integer", "index":false,"ignore_malformed": true  }
      }
    },  
    "index_patterns": ["http_access-*"], 
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "access_log_policy", 
      "index.lifecycle.rollover_alias": "http_access"
    }
  }
  '

fi

curl -u elastic:$password  -X PUT "127.0.0.1:9200/http_access-000001?pretty" -H 'Content-Type: application/json' -d'
{

  "aliases": {
    "http_access":{
      "is_write_index": true 
    }
  }  
}
'

curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/stream_access_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "nid":    { "type": "keyword" },
      "uid":    { "type": "keyword" },
      "upid":    { "type": "keyword" },
      "port":  { "type": "keyword"  }, 
      "addr":  { "type": "keyword"  }, 
      "time":   { "type": "date"  ,"format":"dd/MMM/yyyy:HH:mm:ss Z"},
      "status":  { "type": "keyword"  }, 
      "bytes_sent":  { "type": "integer" , "index":false }, 
      "bytes_received":  { "type": "keyword"  }, 
      "session_time":  { "type": "integer" , "index":false }
    }
  },  
  "index_patterns": ["stream_access-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "access_log_policy", 
    "index.lifecycle.rollover_alias": "stream_access"
  }
}
'
curl -u elastic:$password  -X PUT "127.0.0.1:9200/stream_access-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "stream_access":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/bandwidth_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "nic":  { "type": "keyword"  },
      "inbound":  { "type": "long", "index":false  },
      "outbound":  { "type": "long", "index":false  }
    }
  },  
  "index_patterns": ["bandwidth-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "bandwidth"
  }
}
'
curl -u elastic:$password  -X PUT "127.0.0.1:9200/bandwidth-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "bandwidth":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/nginx_status_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "active_conn":  { "type": "integer" , "index":false }, 
      "reading":  { "type": "integer" , "index":false }, 
      "writing":  { "type": "integer" , "index":false }, 
      "waiting":  { "type": "integer" , "index":false }
    }
  },  
  "index_patterns": ["nginx_status-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "nginx_status"
  }
}
'
curl -u elastic:$password  -X PUT "127.0.0.1:9200/nginx_status-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "nginx_status":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/sys_load_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "cpu":  { "type": "float" , "index":false },
      "load":  { "type": "float" , "index":false },
      "mem":  { "type": "float" , "index":false }
    }
  },  
  "index_patterns": ["sys_load-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "sys_load"
  }
}
'
curl -u elastic:$password  -X PUT "127.0.0.1:9200/sys_load-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "sys_load":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/disk_usage_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "path":  { "type": "keyword"  },
      "space":  { "type": "float" , "index":false },
      "inode":  { "type": "float" , "index":false }      
    }
  },  
  "index_patterns": ["disk_usage-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "disk_usage"
  }
}
'
curl -u elastic:$password  -X PUT "127.0.0.1:9200/disk_usage-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "disk_usage":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "127.0.0.1:9200/_template/tcp_conn_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "conn":  { "type": "integer" , "index":false }
    }
  },  
  "index_patterns": ["tcp_conn-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "tcp_conn"
  }
}
'
curl -u elastic:$password  -X PUT "127.0.0.1:9200/tcp_conn-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "tcp_conn":{
      "is_write_index": true 
    }
  } 
}
'

# 从50006版本开始新增server_port
if [[ $VERSION_NUM -ge 50006 ]];then

# pipeline nginx_access_pipeline
  curl -u elastic:$password -X PUT "127.0.0.1:9200/_ingest/pipeline/nginx_access_pipeline?pretty" -H 'Content-Type: application/json' -d'
  {
    "description" : "nginx access pipeline",
    "processors" : [
        {
          "grok": {
            "field": "message",
            "patterns": ["%{DATA:nid}\t%{DATA:uid}\t%{DATA:upid}\t%{DATA:time}\t%{DATA:addr}\t%{DATA:method}\t%{DATA:scheme}\t%{DATA:host}\t%{DATA:server_port}\t%{DATA:req_uri}\t%{DATA:protocol}\t%{DATA:status}\t%{DATA:bytes_sent}\t%{DATA:referer}\t%{DATA:user_agent}\t%{DATA:content_type}\t%{DATA:up_resp_time}\t%{DATA:cache_status}\t%{GREEDYDATA:up_recv}"]
          }
        },
        {
            "remove": {
              "field": "message"
            }      
        }       
    ]
  }
  '
else
  curl -u elastic:$password -X PUT "127.0.0.1:9200/_ingest/pipeline/nginx_access_pipeline?pretty" -H 'Content-Type: application/json' -d'
    {
      "description" : "nginx access pipeline",
      "processors" : [
          {
            "grok": {
              "field": "message",
              "patterns": ["%{DATA:nid}\t%{DATA:uid}\t%{DATA:upid}\t%{DATA:time}\t%{DATA:addr}\t%{DATA:method}\t%{DATA:scheme}\t%{DATA:host}\t%{DATA:req_uri}\t%{DATA:protocol}\t%{DATA:status}\t%{DATA:bytes_sent}\t%{DATA:referer}\t%{DATA:user_agent}\t%{DATA:content_type}\t%{DATA:up_resp_time}\t%{DATA:cache_status}\t%{GREEDYDATA:up_recv}"]
            }
          },
          {
              "remove": {
                "field": "message"
              }      
          }       
      ]
    }
    '
fi

# stream_access_pipeline
curl -u elastic:$password -X PUT "127.0.0.1:9200/_ingest/pipeline/stream_access_pipeline?pretty" -H 'Content-Type: application/json' -d'
{
  "description" : "stream access pipeline",
  "processors" : [
      {
        "grok": {
          "field": "message",
          "patterns": ["%{DATA:nid}\t%{DATA:uid}\t%{DATA:upid}\t%{DATA:port}\t%{DATA:addr}\t%{DATA:time}\t%{DATA:status}\t%{DATA:bytes_sent}\t%{DATA:bytes_received}\t%{GREEDYDATA:session_time}"]
        }
      },
      {
          "remove": {
            "field": "message"
          }      
      } 
  ]
}
'

# monitor_pipeline
curl -u elastic:$password -X PUT "127.0.0.1:9200/_ingest/pipeline/monitor_pipeline?pretty" -H 'Content-Type: application/json' -d'
{
  "description" : "monitor pipeline",
  "processors" : [
      {
        "json" : {
          "field" : "message",
          "add_to_root" : true
        }
      },
      {
          "remove": {
            "field": "message"
          }      
      } 
  ]
}
'

# black_ip
curl -u elastic:$password  -X PUT "127.0.0.1:9200/black_ip" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "site_id":    { "type": "keyword" },  
      "ip":    { "type": "keyword" },  
      "filter":    { "type": "text" , "index":false }, 
      "uid":  { "type": "keyword"  }, 
      "exp":  { "type": "keyword"  }, 
      "create_at":  { "type": "keyword"  }
    }
  }
}
'

# white_ip
curl -u elastic:$password  -X PUT "127.0.0.1:9200/white_ip" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "site_id":    { "type": "keyword" },  
      "ip":    { "type": "keyword" },  
      "exp":  { "type": "keyword"  }, 
      "create_at":  { "type": "keyword"  }
    }
  }
}
'

# auto_swtich
curl -u elastic:$password  -X PUT "127.0.0.1:9200/auto_switch" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "host":  { "type": "text" , "index":false },
      "rule":  { "type": "text" , "index":false },
      "end_at":  { "type": "integer", "index":true }
    }
  }
}
'

# 从50100开始新增两个表
if [[ $VERSION_NUM -ge 50100 ]];then
  curl -u elastic:$password  -X PUT "127.0.0.1:9200/up_res_usage" -H 'Content-Type: application/json' -d'
  {
    "mappings": {
      "properties": {
        "upid":    { "type": "keyword" },  
        "node_id":    { "type": "keyword" },  
        "bandwidth":    { "type": "integer" , "index":false }, 
        "connection":  { "type": "integer" , "index":false }, 
        "time": { "type": "keyword" }
      }
    }
  }
  '

  curl -u elastic:$password  -X PUT "127.0.0.1:9200/up_res_limit" -H 'Content-Type: application/json' -d'
  {
    "mappings": {
      "properties": {
        "upid":    { "type": "keyword" },  
        "node_id":    { "type": "keyword" },  
        "bandwidth":    { "type": "integer" , "index":false }, 
        "connection":  { "type": "integer" , "index":false }, 
        "expire":  { "type": "keyword" }
      }
    }
  }
  '
fi

iptables -D INPUT -p tcp --dport 9200 -j DROP
iptables -D INPUT -p tcp -s 127.0.0.1 -j ACCEPT

