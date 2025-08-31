<?php
include_once("checkout/config/conecta.php");

// Deletando todos os contratos no banco de dados
$sql_deletar = "DELETE FROM Assinatura WHERE status = 'Assinado' OR status = 'Nao assinado'";
if (mysqli_query($conexao, $sql_deletar)) {
    // Excluindo os arquivos do diretório
    $dir = 'assets/upload/contratos/';
    $files = glob($dir . '*.pdf');  // Pega todos os arquivos PDF no diretório

    foreach ($files as $file) {
        if (is_file($file)) {
            unlink($file);  // Deleta o arquivo
        }
    }

    // Redireciona para listaContratos.php com uma mensagem de sucesso
    header("Location: listaContratos.php?status=excluido");
    exit();  // Não se esqueça de chamar exit após o header para interromper a execução
} else {
    // Redireciona para listaContratos.php com uma mensagem de erro
    header("Location: listaContratos.php?status=erro");
    exit();
}
?>
