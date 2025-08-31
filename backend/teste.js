


const axios = require('axios');

const url = 'http://100.64.0.126/ura/cliente.php?cpf_cnpj=';
const cpfcnpj = '82813558591';

axios.get(url + cpfcnpj).then(function (resposta) {
    // aqui acessamos o corpo da resposta:
    console.log(resposta.data.id);
  })
