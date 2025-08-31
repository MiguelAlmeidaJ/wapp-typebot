#!/bin/bash
nohup php /home/deploy/dct/financeiro/cron_agendamento.php > /home/deploy/dct/financeiro/cron_log.txt 2>&1 &
nohup php /home/deploy/dct/financeiro/cron_msg.php > /home/deploy/dct/financeiro/cron_msg.txt 2>&1 &
nohup php /home/deploy/dct/financeiro/checkout/cron.php > /home/deploy/dct/financeiro/checkout/cron.log 2>&1 &
nohup php /home/deploy/dct/financeiro/cron_msg_rotinas.php > /dev/null > /dev/null 2>&1 &
