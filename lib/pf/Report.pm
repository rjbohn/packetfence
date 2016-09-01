package pf::Report;

use Moose;
use SQL::Abstract::More;
use pf::db;
use pf::log;

use constant REPORT => 'Report';

has 'joins', (is => 'rw', isa => 'ArrayRef[Str]', );

has 'searches', (is => 'rw', isa => 'ArrayRef[HashRef]');

has 'base_table', (is => 'rw', isa => 'Str');

has 'columns', (is => 'rw', isa => 'ArrayRef[Str]');

has 'date_field', (is => 'rw', isa => 'Str');

# empty since no queries are prepared upfront
sub Report_db_prepare {}

sub generate_sql_query {
    my ($self, %infos) = @_;
    my $logger = get_logger;

    my $sqla = SQL::Abstract::More->new();
    my $and = [];

    # Date range handling
    push @$and, $self->date_field => { ">", $infos{start_date}} if($infos{start_date});
    push @$and, $self->date_field => { "<", $infos{end_date}} if($infos{end_date});

    # Search handling
    # conditions = [
    #   {
    #       field => "theField",
    #       # Following the SQL standard
    #       operator => "=",
    #       value => "thatsTheValue",
    #
    #   }
    # ]
    if($infos{search}) {
        my $all = $infos{search}{type} eq "all" ? 1 : 0;
        my @conditions = map { $_->{field} => {$_->{operator} => $_->{value}} } @{$infos{search}{conditions}};
        if($all) {
            $logger->debug("Matching for all conditions");
            push @$and, [ -and => \@conditions ];
        }
        else {
            $logger->debug("Matching for any conditions");
            push @$and, \@conditions;
        }
    }

    $infos{page} //= 0;
    $infos{per_page} //= 25;

    my ($sql, @params) = $sqla->select(
        -columns => $self->columns, 
        -from => [
            -join => ($self->base_table, split(" ", join(" ", @{$self->joins}))),
        ],
        -where => [ 
            -and => [
                @$and,
            ]
        ],
        -limit => $infos{per_page},
        -offset => $infos{page} * $infos{per_page},
    );
    return ($sql, \@params);
}

sub query {
    my ($self, %infos) = @_;
    my ($sql, $params) = $self->generate_sql_query(%infos);
    my $print_params = join(", ", map { "'$_'" } @$params);
    get_logger->debug("Executing query : $sql, with the following params : $print_params");
    return db_data(REPORT, {'report_sql' => $sql}, 'report_sql', @$params);
}

1;

