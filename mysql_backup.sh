#!/bin/bash

# editer: even
# version: 1.1.3 release

# 修改需要备份的所有库名(空格分隔，库名包在单引号内),想备份所有数据库使用'all'
DB_NAME = ('all')

# 筛选方式，1为正向筛选，0为反向筛选
FILTER_METHOD = 1

# 修改待备份数据库地址，端口，用户，密码。label用作标识该数据库，便于识别备份的文件
DB_HOST = '192.168.1.218'
DB_PORT = 3306
DB_USER = 'root'
DB_PASSWORD = ''
DB_LABEL = 'db_1.218'

# 修改备份到远程服务器scp地址，端口，用户，密码,REMOTE_BACKUP为1代表开启远程备份，0关闭
REMOTE_BACKUP = 1
REMOTE_HOST = '192.168.1.168'
REMOTE_PORT = 22
REMOTE_USER = 'root'
REMOTE_KEY = '/root/.ssh/id_rsa'
REMOTE_PATH = '/backup/'

# 删除n天前的文件(未成功备份的天数不计算在内)
SAVE_DAY = 7

# 修改mysql执行文件的所在路径
MYSQL_EXEC_PATH = '/usr/bin/'

# 修改备份，日志文件存放位置
DB_SAVE_PATH = '/root/mysql_backup/db_data/'
DB_LOGS = '/root/mysql_backup/logs/'


function main(){ 
	DBS=$(/usr/bin/mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} -Bse "show databases" \
	 | grep -v "information_schema" \
	 | grep -v "performance_schema" \
	 | grep -v "mysql" \
	 | grep -v "sys" \
	 )

	for dbname in ${DB_NAME[@]}; do
		DATE = $(date +%Y-%m-%d_%H%M%S)
		FILENAME_NO_DATE = ${dbname}_${DB_LABEL}
		FILENAME = ${FILENAME_NO_DATE}_${date}

		mkdir -p ${DB_SAVE_PATH}/${dbname}
		mkdir -p ${DB_LOGS}
		touch ${DB_LOGS}/mysql_backup_access.log
		touch ${DB_LOGS}/mysql_backup_failed.log

		echo 'do backup...'${FILENAME}

		${MYSQL_EXEC_PATH}/mysqldump -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} -R -E --triggers ${dbname} > sqldump.out 2> sqldump.err

		cat sqldump.err | grep error
		e = $?
		if [ -s sqldump.err -a ${e} == 0 ]; then
			cat sqldump.out >> ${DB_LOGS}/mysql_backup_failed.log
			cat sqldump.err | xargs -I {} -0  echo "$(date '+%Y-%m-%d %H:%M:%S') ${dbname} {}" >> ${DB_LOGS}/mysql_backup_failed.log
			exit 1
		fi

		if [ -s sqldump.out ]; then
			cat sqldump.out | gzip > ${DB_SAVE_PATH}/${dbname}/${FILENAME}.sql.gz 2>> ${DB_LOGS}/mysql_backup_failed.log
		fi

		ls ${DB_SAVE_PATH}/${dbname}/ | grep ${DATE}
		if [ $? == 0 ]; then
			if [ ${REMOTE_BACKUP} == 1 ]; then
				send_to_other
			fi
			echo "$(date '+%Y-%m-%d %H:%M:%y') ${dbname} backup success" | tee -a ${DB_LOGS}/mysql_backup_access.log
			del
		else
			echo "$(date '+%Y-%m-%d %H:%M:%y') ${dbname} backup failed" | tee -a ${DB_LOGS}/mysql_backup_failed.log
		fi
	
		rm -f sqldump.out sqldump.err
	done
	exit 0
}

function is_linux(){
	ssh -i ${REMOTE_KEY} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "uname -a"
	if [ $? == 0 ]; then
		return true
	else
		return false
}

function del(){
	# 删除SAVE_DAY天前的文件,i为保留的份数，d为天数
	declare -i i = 1
	declare -i d = 0
	while [ ${i} != ${SAVE_DAY} ] 
	do
		ls ${DB_SAVE_PATH}/${dbname}/ | grep $(date +%Y-%m-%d -d '-'${d}'day')
		if [ $? == 0 ];then
			i += 1
		fi
		d += 1
		if [ ${d} -ge 30 ];then
			echo "$(date '+%Y-%m-%d %H:%M:%y') ${d}bname cannot found old db backup in 1 month" | tee ${DB_LOGS}/mysql_backup_failed.log
			return 1
		fi
	done
	# 删除本地旧备份
	find ${DB_SAVE_PATH}/${dbname}/ -mtime +${d} -type f -name ${FILENAME_NO_DATE}*.sql.gz -delete
	is_true = $(find ${DB_SAVE_PATH}/${dbname}/ -mtime +${d} -type f -name ${FILENAME_NO_DATE}*.sql.gz)
	if [ ! -z ${is_true} ]; then
		echo "$(date '+%Y-%m-%d %H:%M:%y') ${dbname} local old db clean failed" | tee -a ${DB_LOGS}/mysql_backup_failed.log
	fi
	# 删除异机旧备份
	if [ ${REMOTE_BACKUP} == 1 ];then
		is_linux
		if [ $? is true ];then
			ssh -i ${REMOTE_KEY} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "find ${REMOTE_PATH} -mtime +${d} -type f -name ${FILENAME_NO_DATE}*.sql.gz -delete" 2>> $DB_LOGS/mysql_backup_failed.log
			is_true = $(ssh -i ${REMOTE_KEY} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "find ${REMOTE_PATH} -mtime +${d} -type f -name ${FILENAME_NO_DATE}*.sql.gz")
		else
			ssh -i ${REMOTE_KEY} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "(Get-ChildItem -path ${REMOTE_PATH} -filter ${FILENAME_NO_DATE}*.sql.gz|where {\$_.LastWriteTime -le (get-date).adddays($(expr 0 - ${SAVE_DAY} - 1)) -and \$_ -is [System.IO.FileInfo]}).fullname|Remove-Item" 2>> $DB_LOGS/mysql_backup_failed.log
			is_true = $(ssh -i ${REMOTE_KEY} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "((Get-ChildItem ${REMOTE_PATH} -filter ${FILENAME_NO_DATE}*.sql.gz).LastWriteTime).AddDays($(expr 0 - ${SAVE_DAY} - 1))")
		fi

		if [ ! -z ${is_true} ]; then
			echo "$(date '+%Y-%m-%d %H:%M:%y') ${d}bname remote old db clean failed" | tee -a ${DB_LOGS}/mysql_backup_failed.log
		fi
	fi
	unset i d
}

function send_to_other(){
	is_linux
	if [ $? == 0 ]; then
		ssh -i ${REMOTE_KEY} -P ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_PATH}/${dbname}"
	else
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		ssh -i ${REMOTE_KEY} -P ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_PATH}/${dbname}"
	scp -r -i ${REMOTE_KEY} -P ${REMOTE_PORT} ${DB_SAVE_PATH}/${dbname}/${FILENAME}.sql.gz ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${dbname}/ 2>> ${DB_LOGS}/mysql_backup_failed.log
}

main