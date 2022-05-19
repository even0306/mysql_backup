#!/bin/bash

# editer: even
# version: 1.1.3 release

# 修改需要备份的所有库名(空格分隔，库名包在单引号内),想备份所有数据库使用'--all-databases'
db_name=('--all-databases')

# 修改待备份数据库地址，端口，用户，密码。label用作标识该数据库，便于识别备份的文件
db_host='192.168.1.218'
db_port=3306
db_user=root
db_pwd=''
db_label='db_1.218'

# 修改备份到远程服务器scp地址，端口，用户，密码,remote_backup为1代表开启远程备份，0关闭
remote_backup=1
remote_host='192.168.1.168'
remote_port=22
remote_user=root
remote_key='/root/.ssh/id_rsa'
remote_path=/backup/

# 删除n天前的文件(未成功备份的天数不计算在内)
rmDay=7

# 修改mysqldump文件的所在路径
mysqldumpPath=/usr/bin/

# 修改备份，日志文件存放位置
db_savePath=/root/mysql_backup/db_data/
db_logs=/root/mysql_backup/logs/


main(){ 
	for dbname in ${db_name[@]}; do
		date=$(date +%Y-%m-%d_%H%M%S)
		fileNameNoDate=${dbname}_${db_label}
		if [ ${dbname} == "--all-databases" ];then
			fileNameNoDate=allDatabases_${db_label}
			filePath=allDatabases
		fi
		fileName=${fileNameNoDate}_${date}

		mkdir -p $db_savePath/${filePath}
		mkdir -p $db_logs
		touch $db_logs/mysql_backup_access.log
		touch $db_logs/mysql_backup_failed.log

		echo 'do backup...'$fileName

		$mysqldumpPath/mysqldump -h$db_host -P$db_port -u$db_user -p$db_pwd -R -E --triggers $dbname > sqldump.out 2> sqldump.err

		cat sqldump.err | grep error
		e=$?
		if [ -s sqldump.err -a ${e} == 0 ]; then
			cat sqldump.out >> $db_logs/mysql_backup_failed.log
			cat sqldump.err | xargs -I {} -0  echo "$(date '+%Y-%m-%d %H:%M:%S') $dbname {}" >> $db_logs/mysql_backup_failed.log
			exit 1
		fi

		if [ -s sqldump.out ]; then
			cat sqldump.out | gzip > $db_savePath/${filePath}/${fileName}.sql.gz 2>> $db_logs/mysql_backup_failed.log
		fi

		ls $db_savePath/${filePath}/ | grep $date
		if [ $? == 0 ]; then
			if [ ${remote_backup} == 1 ]; then
				sendToOther
			fi
			echo "$(date '+%Y-%m-%d %H:%M:%y') $dbname backup success" | tee -a $db_logs/mysql_backup_access.log
			del
		else
			echo "$(date '+%Y-%m-%d %H:%M:%y') $dbname backup failed" | tee -a $db_logs/mysql_backup_failed.log
		fi
	
		rm -f sqldump.out sqldump.err
	done
	exit 0
}

del(){
	# 删除rmDay天前的文件,i为保留的份数，d为天数
	declare -i i=1
	declare -i d=0
	while [ $i != $rmDay ] 
	do
		ls $db_savePath/${filePath}/ | grep $(date +%Y-%m-%d -d '-'$d'day')
		if [ $? == 0 ];then
			i+=1
		fi
		d+=1
		if [ $d -ge 30 ];then
			echo "$(date '+%Y-%m-%d %H:%M:%y') $dbname cannot found old db backup in 1 month" | tee -a $db_logs/mysql_backup_failed.log
			return 1
		fi
	done
	# 删除本地旧备份
	find $db_savePath/${filePath}/ -mtime +$d -type f -name ${fileNameNoDate}*.sql.gz -delete
	isTrue=$(find $db_savePath/${filePath}/ -mtime +$d -type f -name ${fileNameNoDate}*.sql.gz)
	if [ ! -z ${isTrue} ]; then
		echo "$(date '+%Y-%m-%d %H:%M:%y') $dbname local old db clean failed" | tee -a $db_logs/mysql_backup_failed.log
	fi
	# 删除异机旧备份
	if [ ${remote_backup} == 1 ];then
		ssh -i ${remote_key} -p ${remote_port} ${remote_user}@${remote_host} "uname -a"
		if [ $? == 0 ];then
			ssh -i ${remote_key} -p ${remote_port} ${remote_user}@${remote_host} "find ${remote_path} -mtime +$d -type f -name ${fileNameNoDate}*.sql.gz -delete" 2>> $db_logs/mysql_backup_failed.log
			isTrue=$(ssh -i ${remote_key} -p ${remote_port} ${remote_user}@${remote_host} "find ${remote_path} -mtime +$d -type f -name ${fileNameNoDate}*.sql.gz")
		else
			ssh -i ${remote_key} -p ${remote_port} ${remote_user}@${remote_host} "(Get-ChildItem -path ${remote_path} -filter ${fileNameNoDate}*.sql.gz|where {\$_.LastWriteTime -le (get-date).adddays($(expr 0 - ${rmDay} - 1)) -and \$_ -is [System.IO.FileInfo]}).fullname|Remove-Item" 2>> $db_logs/mysql_backup_failed.log
			isTrue=$(ssh -i ${remote_key} -p ${remote_port} ${remote_user}@${remote_host} "((Get-ChildItem ${remote_path} -filter ${fileNameNoDate}*.sql.gz).LastWriteTime).AddDays($(expr 0 - ${rmDay} - 1))")
		fi

		if [ ! -z ${isTrue} ]; then
			echo "$(date '+%Y-%m-%d %H:%M:%y') $dbname remote old db clean failed" | tee -a $db_logs/mysql_backup_failed.log
		fi
	fi
	unset i d
}

sendToOther(){
	scp -i ${remote_key} -P ${remote_port} $db_savePath/${filePath}/${fileName}.sql.gz ${remote_user}@${remote_host}:${remote_path} 2>> $db_logs/mysql_backup_failed.log
}

main
