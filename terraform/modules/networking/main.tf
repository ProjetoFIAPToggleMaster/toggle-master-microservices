locals {
  az_count = length(var.availability_zones)

  # Layout de endereçamento: as N primeiras faixas /(<prefixo>+newbits) ficam
  # com as subnets públicas; as N seguintes, com as privadas.
  public_subnet_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, var.subnet_newbits, i)]
  private_subnet_cidrs = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, var.subnet_newbits, i + local.az_count)]

  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  # Uma route table privada por NAT Gateway; se não há NAT, uma única RT
  # privada isolada (sem rota default).
  private_route_table_count = max(local.nat_gateway_count, 1)

  eks_discovery_tags = var.eks_cluster_name != "" ? {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  } : {}
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# ---------------------------------------------------------------------------
# Subnets públicas
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    var.tags,
    local.eks_discovery_tags,
    {
      Name                     = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
      Tier                     = "public"
      "kubernetes.io/role/elb" = "1"
    },
  )
}

# ---------------------------------------------------------------------------
# Subnets privadas
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    local.eks_discovery_tags,
    {
      Name                              = "${var.name_prefix}-private-${var.availability_zones[count.index]}"
      Tier                              = "private"
      "kubernetes.io/role/internal-elb" = "1"
    },
  )
}

# ---------------------------------------------------------------------------
# NAT Gateway(s) + Elastic IP(s)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route table pública (rota default -> Internet Gateway)
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Route table(s) privada(s) (rota default -> NAT Gateway, quando habilitado)
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count = local.private_route_table_count

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = local.private_route_table_count > 1 ? "${var.name_prefix}-private-rt-${var.availability_zones[count.index]}" : "${var.name_prefix}-private-rt"
  })
}

resource "aws_route" "private_nat" {
  count = local.nat_gateway_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id = aws_subnet.private[count.index].id
  # single NAT (ou sem NAT) => todas as subnets na RT 0.
  # NAT por AZ => cada subnet na RT correspondente.
  route_table_id = aws_route_table.private[local.private_route_table_count > 1 ? count.index : 0].id
}
