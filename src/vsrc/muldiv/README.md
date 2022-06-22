# 除法器使用方法

```
    case(para)
     3'h0 : md_out =    $signed(rs0) *   $signed(rs1);
     3'h1 : md_out = (  $signed(rs0) *   $signed(rs1))>>`XLEN;
     3'h2 : md_out =      signed_mul_unsigned(rs0,rs1)>>`XLEN;//(  $signed(rs0) * $unsigned(rs1))>>32;
     3'h3 : md_out = ($unsigned(rs0) * $unsigned(rs1))>>`XLEN;
     3'h4 : md_out =    $signed(rs0) /   $signed(rs1);
     3'h5 : md_out =  $unsigned(rs0) / $unsigned(rs1);
     3'h6 : md_out =    $signed(rs0) %   $signed(rs1);
     3'h7 : md_out =  $unsigned(rs0) % $unsigned(rs1);
 endcase 
```
