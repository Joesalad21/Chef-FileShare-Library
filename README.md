# Chef-FileShare-Library

#### This is a simple Ruby library that utilizes a Chef "host" attribute that is set on a node basis using the IP of the node. Once the library determines whether the machine is hosted on a local or Amazon subnet, it will either use the Ruby AWS SDK to pull from an S3 bucket, or use the Winole resource to mount a virtual drive and pull from a local file share.