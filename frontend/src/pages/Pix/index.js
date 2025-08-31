import React, { useContext } from "react";
import { AuthContext } from "../../context/Auth/AuthContext";

const Pix = () => {
  const { user } = useContext(AuthContext);

  // Monta a URL com o user.id, se disponível
  const url = user?.id 
    ? `https://financeiro.skynetfibra.net.br/listarPix.php?id=${user.id}` 
    : "https://financeiro.skynetfibra.net.br/listarPix.php"; // URL padrão caso o user.id não exista

  console.log(user?.id); // Exibe o user.id no console

  return (
    <iframe 
      width="100%" 
      height="91.3%" 
      src={url}  // Passa a URL dinamicamente para o iframe
      frameBorder="0" 
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" 
      referrerPolicy="strict-origin-when-cross-origin" 
      allowFullScreen
    ></iframe>
  );
};

export default Pix;
