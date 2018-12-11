module AWS
  def self.pullFromS3(filePath, targetPath)
    require 'aws-sdk-s3'
    require 'digest/md5'
    require 'fileutils'

    # Determine if working with Windows or Linux and set base directory
    if Chef::Platform.windows?
      basedir = "c:"
      ext = ".txt"
    else
      basedir = "/etc"
      ext = ""
    end
    
    # Some prep work
    dbag = Chef::EncryptedDataBagItem.load("dbag_hm_base", "aws")
    accesskey = dbag["accesskey"]
    accesssecret = dbag["accesssecret"]
    bucketname = "somebucketname"
    fileName = File.basename(filePath)
    
    # Create new instance of S3 with proper credentials
    s3 = Aws::S3::Resource.new(
    region: 'us-east-1',
    access_key_id: accesskey,
    secret_access_key: accesssecret
  )
  
    # Grabs the Etag, and creates dirs if they do not exist
    if s3.bucket(bucketname).object(filePath).exists?
      etag = s3.bucket(bucketname).object(filePath).etag.delete('"')
      FileUtils::mkdir_p "#{basedir}/chef/etag"
      FileUtils::mkdir_p "#{basedir}/chef/md5"
      FileUtils.touch("#{basedir}/chef/etag/#{fileName}#{ext}")
      FileUtils.touch("#{basedir}/chef/md5/#{fileName}#{ext}")
      
      # Some basic file handling
      file = File.open("#{basedir}/chef/etag/#{fileName}#{ext}", 'r')
      fileMD5 = File.open("#{basedir}/chef/md5/#{fileName}#{ext}", 'r')
      content = file.read
      contentMD5 = fileMD5.read
    
      # If the file does not exist in #{basedir}/chef/cache, downloads the file and writes the Etag/MD5
      if !File.exist?(targetPath + fileName)
        puts 'File ' + fileName + ' not found in ' + targetPath + '... Copying from S3 bucket.'
        file.close
        file = File.open("#{basedir}/chef/etag/#{fileName}#{ext}", 'w')
        file.write(etag)
        file.close
        s3.bucket(bucketname).object(filePath).get(response_target: targetPath + fileName)
        fileMD5.close
        fileMD5 = File.open("#{basedir}/chef/md5/#{fileName}#{ext}", 'w')
        fileMD5.write(Digest::MD5.file(targetPath + fileName).hexdigest)
        fileMD5.close
      # If the file does exist, but the Etag OR the MD5 do not match, deletes old file and downloads new
      elsif File.exist?(targetPath + fileName) && ((etag != content) || ((Digest::MD5.file(targetPath + fileName).hexdigest) != contentMD5))
        puts 'File ' + fileName + ' found, but Etag/MD5 doesn\'t match... Copying from S3 bucket.'
        file.close
        file = File.open("#{basedir}/chef/etag/#{fileName}#{ext}", 'w')
        file.write(etag)
        file.close
        FileUtils.chmod(0755, targetPath + fileName)
        FileUtils.rm(targetPath + fileName, :force => true)
        s3.bucket(bucketname).object(filePath).get(response_target: targetPath + fileName)
        fileMD5.close
        fileMD5 = File.open("#{basedir}/chef/md5/#{fileName}#{ext}", 'w')
        fileMD5.write(Digest::MD5.file(targetPath + fileName).hexdigest)
        fileMD5.close
      # If the file does exist, and the Etag AND MD5 both match, does nothing
      else
        puts 'File ' + fileName + ' found, and Etag/MD5 matches... Nothing to do.'
        file.close
        fileMD5.close
      end
    else
      puts "#{filePath} does not exist in the S3 bucket!"
    end
  end
end

module FileShare
  def self.getFile(host, filePath, targetPath="c:/chef/cache")
    if Chef::Platform.windows?
      require 'win32ole'
    end

    require 'digest/md5'
    require 'fileutils'
    
    if !Dir.exists?(targetPath)
      FileUtils.mkdir_p targetPath
    end

    if !targetPath.end_with? "/"
      if !targetPath.end_with? "\\"
        targetPath = targetPath + "/"
      end
    end
    
    if Chef::Platform.windows?
      net = WIN32OLE.new('WScript.Network')
      dbagSA = Chef::EncryptedDataBagItem.load("serviceAccts", "chef")
      saUser = "DOMAIN\\servicerAccount"
      saPass = dbagSA["password"]
    
      # Parse the file name from the file path
      fileName = File.basename(filePath)
      netDrive = "J:"
      netShare = "\\\\fqdn_of_windows_file_share\\#{bucketname}"
    end
    
    # Mounts the network drive if HM/CTL machine and if it doesn't exist, pulls the file
    case host
    when 'hm', 'ctl'
      if Chef::Platform.windows?
        # Maps network drive if it does not already exist
        if !Dir.exists?(netDrive)
          net.MapNetworkDrive( netDrive, netShare, false, saUser, saPass )
        end
        # Check to see if file exists on J drive. If not, skips it.
        if !File.exist?(netDrive + '/' + filePath)
          puts netDrive + '/' + filePath + 'does not exist!'
        else
          # Pulls file to chef cache if not already there
          if !File.exist?(targetPath + fileName)
            puts 'File ' + fileName + ' not found in ' + targetPath + '... Copying from network share.'
            FileUtils.cp(netDrive + '/' + filePath, targetPath + fileName)
          # Compares MD5 hash if file already exists. If they don't match, pulls from network share.
          elsif File.exist?(targetPath + fileName) && (Digest::MD5.file(netDrive + '/' + filePath).hexdigest != Digest::MD5.file(targetPath + fileName).hexdigest)
            puts 'File ' + fileName + ' found, but MD5 doesn\'t match... Copying from network share.'
            FileUtils.chmod(0755, targetPath + fileName)
            FileUtils.rm(targetPath + fileName, :force => true)
            FileUtils.cp(netDrive + '/' + filePath, targetPath + fileName)
          else
            puts 'File ' + fileName + ' found, and MD5 matches... Nothing to do.'
          end
        end
        # Unmount network share
        if Dir.exists?(netDrive)
          net.RemoveNetworkDrive( netDrive, true, true )
        end
      end
    when 'ec2'
      AWS.pullFromS3(filePath, targetPath)
    else
      puts 'Cannot properly determine host. Contact Chef guru...'
    end
  end
end