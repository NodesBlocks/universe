#!/bin/bash
# By Dimokus (https://t.me/Dimokus)
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
(echo ${my_root_password}; echo ${my_root_password}) | passwd root && service ssh restart
sleep 5
runsvdir -P /etc/service &
if [[ -n $SNAP_RPC ]]
then 
chain=`curl -s "$SNAP_RPC"/genesis | jq -r .result.genesis.chain_id`
denom=`curl -s "$SNAP_RPC"/genesis | grep denom -m 1 | tr -d \"\, | sed "s/denom://" | tr -d \ `
folder=`curl -s "$SNAP_RPC"/abci_info | jq -r .result.response.data`
folder=`echo $folder | sed "s/$folder/.$folder/"`
vers=`curl -s "$SNAP_RPC"/abci_info | jq -r .result.response.version`
fi

echo $chain
echo $denom
echo $folder
echo $vers
sleep 10
echo 'export MONIKER='${MONIKER} >> /root/.bashrc
echo 'export CHAT_ID='${CHAT_ID} >> /root/.bashrc
echo 'export denom='${denom} >> /root/.bashrc
echo 'export chain='${chain} >> /root/.bashrc
echo 'export SNAP_RPC='${SNAP_RPC} >> /root/.bashrc
source /root/.bashrc
#======================================================== НАЧАЛО БЛОКА ФУНКЦИЙ ==================================================
#-------------------------- Установка GO и кмопиляция бинарного файла -----------------------
INSTALL (){
#-----------КОМПИЛЯЦИЯ БИНАРНОГО ФАЙЛА------------
cd /root/
git clone $gitrep && cd $gitfold
echo $vers
sleep 5
git checkout $vers
sudo make build
sudo make install
binary=`ls /root/go/bin`
if [[ -z $binary ]]
then
binary=`ls /root/$gitfold/build/`
fi
echo $binary
echo 'export binary='${binary} >> /root/.bashrc
cp /root/$gitfold/build/$binary /usr/bin/$binary
cp /root/go/bin/$binary /usr/bin/$binary
$binary version
#-------------------------------------------------

#=======ИНИЦИАЛИЗАЦИЯ БИНАРНОГО ФАЙЛА================
echo =INIT=
rm /root/$folder/config/genesis.json
$binary init "$MONIKER" --chain-id $chain --home /root/$folder
sleep 5
$binary config chain-id $chain
$binary config keyring-backend os
#====================================================

#===========ДОБАВЛЕНИЕ GENESIS.JSON===============
if [[ -n $SNAP_RPC ]]
then 
rm /root/$folder/config/genesis.json
curl -s "$SNAP_RPC"/genesis | jq .result.genesis >> /root/$folder/config/genesis.json
else
rm /root/$folder/config/genesis.json
wget -O /root/$folder/config/genesis.json $genesis
sha256sum ~/$folder/config/genesis.json
cd && cat $folder/data/priv_validator_state.json
fi
#=================================================

#-----ВНОСИМ ИЗМЕНЕНИЯ В CONFIG.TOML , APP.TOML.-----------

if [[ -n $SNAP_RPC ]]
then
n_peers=`curl -s $SNAP_RPC/net_info? | jq -r .result.n_peers`
let n_peers="$n_peers"-1
RPC="$SNAP_RPC"
echo -n "$RPC," >> /root/RPC.txt
p=0
count=0
echo "Search peers..."
while [[ "$p" -le  "$n_peers" ]] && [[ "$count" -le  14 ]]
do
	PEER=`curl -s  $SNAP_RPC/net_info? | jq -r .result.peers["$p"].node_info.listen_addr`
        if [[ ! "$PEER" =~ "tcp" ]] 
        then
			id=`curl -s  $SNAP_RPC/net_info? | jq -r .result.peers["$p"].node_info.id`
            		echo -n "$id@$PEER," >> /root/PEER.txt
			echo $id@$PEER
			rm /root/addr.tmp
			echo $PEER | sed 's/:/ /g' > /root/addr.tmp
			ADDRESS=(`cat /root/addr.tmp`)
			ADDRESS=`echo ${ADDRESS[0]}`
			PORT=(`cat /root/addr.tmp`)
			PORT=`echo ${PORT[1]}`
			let PORT=$PORT+1
			RPC=`echo $ADDRESS:$PORT`
			let count="$count"+1
			if [[ `curl -s http://$RPC/abci_info? --connect-timeout 5 | jq -r .result.response.last_block_height` -gt 0 ]]
			then
				echo "$RPC"
				echo -n "$RPC," >> /root/RPC.txt
				RPC=0
			fi
			RPC=0
   	     fi
	p="$p"+1
	done
echo "Search peers is complete!"
PEER=`cat /root/PEER.txt | sed 's/,$//'`
RPC=`cat /root/RPC.txt | sed 's/,$//'`
else
	if [[ -n $link_peer ]]
	then
		PEER=`curl -s $link_peer`
	fi

	if [[ -n $link_seed ]]
	then
		SEED=`curl -s $link_seed`
	fi
fi
echo $PEER
echo $SEED
sleep 5
sed -i.bak -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.0025$denom\"/;" /root/$folder/config/app.toml
sleep 1
sed -i.bak -e "s/^seeds *=.*/seeds = \"$SEED\"/;" /root/$folder/config/config.toml
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEER\"/;" /root/$folder/config/config.toml
sed -i.bak -e "s_"tcp://127.0.0.1:26657"_"tcp://0.0.0.0:26657"_;" /root/$folder/config/config.toml
pruning="custom" && \
pruning_keep_recent="5" && \
pruning_keep_every="1000" && \
pruning_interval="50" && \
sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" /root/$folder/config/app.toml && \
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" /root/$folder/config/app.toml && \
sed -i -e "s/^pruning-keep-every *=.*/pruning-keep-every = \"$pruning_keep_every\"/" /root/$folder/config/app.toml && \
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" /root/$folder/config/app.toml
snapshot_interval="1000" && \
sed -i.bak -e "s/^snapshot-interval *=.*/snapshot-interval = \"$snapshot_interval\"/" /root/$folder/config/app.toml
#-----------------------------------------------------------

#|||||||||||||||||||||||||||||||||||ФУНКЦИЯ Backup||||||||||||||||||||||||||||||||||||||||||||||||||||||
# ====================RPC======================
if [[ -n $SNAP_RPC ]]
then
	RPC=`echo $SNAP_RPC,$RPC`
	echo $RPC
	LATEST_HEIGHT=`curl -s $SNAP_RPC/block | jq -r .result.block.header.height`; \
	BLOCK_HEIGHT=$((LATEST_HEIGHT - $SHIFT)); \
	TRUST_HASH=$(curl -s "$SNAP_RPC/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)
	echo $LATEST_HEIGHT $BLOCK_HEIGHT $TRUST_HASH
	sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
	s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$RPC\"| ; \
	s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
	s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"|" /root/$folder/config/config.toml
	echo RPC
fi
#================================================
# |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
wget -O /tmp/priv_validator_key.json ${LINK_KEY}
file=/tmp/priv_validator_key.json
if  [[ -f "$file" ]]
then
	      sleep 2
	      cd /
	      rm /root/$folder/config/priv_validator_key.json
	      echo ==========priv_validator_key found==========
	      echo ========Обнаружен priv_validator_key========
	      cp /tmp/priv_validator_key.json /root/$folder/config/
	      echo ========Validate the priv_validator_key.json file=========
	      echo ==========Сверьте файл priv_validator_key.json============
	      cat /tmp/priv_validator_key.json
	      sleep 10
    else     	
    	echo "==================================================================================="
	echo "======== priv_validator_key not found! Specify direct download link ==============="
	echo "===== of the validator key file in the LINK_KEY variable in your deploy.yml ======="
	echo "===== If you don't have a key file, use the instructions at the link below ======="
	echo "== https://github.com/Dimokus88/guides/blob/main/Cosmos%20SDK/valkey/README.md ===="
	echo "==================================================================================="
	echo "========  priv_validator_key ненайден! Укажите ссылку напрямое скачивание  ========"
	echo "========  файла ключа валидатора в переменной LINK_KEY в вашем deploy.yml  ========"
	echo "=====  Если у вас нет файла ключа, воспользуйтесь инструкцией по ссылке ниже ====="
	echo "== https://github.com/Dimokus88/guides/blob/main/Cosmos%20SDK/valkey/README.md ===="
	echo "==================================================================================="
	echo "============= The node is running with the generated validator key! ==============="
	echo "==================================================================================="
	echo "================= Нода запущена с сгенерированным ключом валидатора! =============="
	echo "==================================================================================="
	RUN
	sleep infinity 	
    fi
}

RUN (){
#===========ЗАПУСК НОДЫ============
echo =Run node...=
cd /
mkdir /root/$binary
mkdir /root/$binary/log
    
cat > /root/$binary/run <<EOF 
#!/bin/bash
exec 2>&1
exec $binary start
EOF
chmod +x /root/$binary/run
LOG=/var/log/$binary

cat > /root/$binary/log/run <<EOF 
#!/bin/bash
mkdir $LOG
exec svlogd -tt $LOG
EOF
chmod +x /root/$binary/log/run
ln -s /root/$binary /etc/service
}
#--------------------------------------------------------------------------------------------
#======================================================== КОНЕЦ БЛОКА ФУНКЦИЙ ====================================================
INSTALL
sleep 15
RUN
sleep 30
catching_up=`curl -s localhost:26657/status | jq -r .result.sync_info.catching_up`
while [[ $catching_up == true ]]
do
echo == Нода не синхронизирована ==
sleep 2m
catching_up=`curl -s localhost:26657/status | jq -r .result.sync_info.catching_up`
echo $catching_up
done
#=====Включение алерт бота =====

if [[ -n $CHAT_ID ]] && [[ -n $TOKEN ]]
then
apt install -y python3 pip
pip install pyTelegramBotAPI
sleep 10
echo == Включение оповещение Telegram ==
mkdir /root/bot/
mkdir /root/bot/tmp/
source ~/.bashrc && curl -s https://raw.githubusercontent.com/Dimokus88/universe/main/script/parameters.sh | bash
wget -O /root/bot/status.sh https://raw.githubusercontent.com/Dimokus88/universe/main/bots/status.sh && chmod +x /root/bot/status.sh
cat > /root/bot/CosmoBot.py <<EOF 
import telebot
from telebot import types
import os
import subprocess
bot = telebot.TeleBot("$TOKEN")
binary = os.getenv('binary')
@bot.message_handler(commands=['start'])
def start_message(message):
        bot.send_message(message.chat.id,"Welcome to Akash Nodes Alert Bot!")
        markup=types.ReplyKeyboardMarkup(resize_keyboard=True)
        item1=types.KeyboardButton("Status")
        markup.add(item1)
        bot.send_message(message.chat.id,"Select functions please!",reply_markup=markup)

@bot.message_handler(content_types=['text'])
def handle_text(message):
        if message.text == "Status":
                subprocess.check_call("/root/bot/status.sh '%s'" % binary, shell=True)
                text = open ('/root/bot/text.txt')
                bot.send_message(message.chat.id,text.read())
bot.infinity_polling()
EOF
chmod +x /root/bot/CosmoBot.py

mkdir /root/bot/log
sleep 5  
cat > /root/bot/run <<EOF 
#!/bin/bash
exec 2>&1
export binary=$binary
exec python3 /root/bot/CosmoBot.py
EOF
chmod +x /root/bot/run
LOG=/var/log/bot

cat > /root/bot/log/run <<EOF 
#!/bin/bash
mkdir $LOG
exec svlogd -tt $LOG
EOF
chmod +x /root/bot/log/run
ln -s /root/bot /etc/service
sleep 5
echo == Оповещение Telegram включено ==
sleep 5
echo == Установка cheker proposal ==
mkdir /root/tmp/
mkdir /root/cheker/
wget -O /root/cheker/cheker_proposal.sh https://raw.githubusercontent.com/Dimokus88/universe/main/script/cheker_proposal.sh && chmod +x /root/cheker/cheker_proposal.sh
mkdir /root/cheker/log
sleep 5  
cat > /root/cheker/run <<EOF 
#!/bin/bash
exec 2>&1
exec /root/cheker/cheker_proposal.sh $binary $TOKEN $CHAT_ID 
EOF
chmod +x /root/cheker/run
LOG=/var/log/cheker

cat > /root/cheker/log/run <<EOF 
#!/bin/bash
mkdir $LOG
exec svlogd -tt $LOG
EOF
chmod +x /root/cheker/log/run
ln -s /root/cheker /etc/service
sleep 5
echo == Cheker proposal установлен ==
fi
#==============================
sleep 1m
# -----------------------------------------------------------
for ((;;))
  do    
    tail -100 /var/log/$binary/current | grep -iv peer
    sleep 10m
  done
fi
